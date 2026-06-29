package db

import (
	"context"
	"log/slog"
)

// EnsureCredentialModelIndexArchive ensures the credential_model_index_archive
// tiered-storage parent table exists for historical data older than 7 days.
//
// Architecture:
//  - Main table (credential_model_index): keeps recent 7 days, heap, supports ON CONFLICT
//  - Archive table (credential_model_index_archive): 7+ days old, columnar partitions, read-only
//
// On first boot, the archive table is created along with helper functions:
//  - archive_credential_model_index(month date) - archives 7d+ data to columnar for given month
//  - cleanup_old_credential_model_index() - daily cleanup, removes 7d+ data from main table
//  - ensure_next_month_cmi_archive_partition() - pre-creates next month columnar partition
//
// All DDL is idempotent: CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE FUNCTION.
//
// After this ensure runs:
//  - public.credential_model_index_archive (heap parent, RANGE by bucket)
//  - Helper functions for archival, cleanup, and partition management
//
// See deploy/sql/migrations/922_credential_model_index_archive.sql for the standalone
// migration that does the same thing from psql.
func (d *DB) EnsureCredentialModelIndexArchive(ctx context.Context) error {
	if d == nil || d.pool == nil {
		return nil
	}
	_, err := d.pool.Exec(ctx, `
		-- credential_model_index_archive parent table (heap, RANGE by bucket).
		-- Stores historical data (7+ days old) in columnar partitions.
		-- Main table keeps recent 7 days with ON CONFLICT support for live updates.
		CREATE TABLE IF NOT EXISTS public.credential_model_index_archive (
		    bucket timestamp with time zone NOT NULL,
		    credential_id bigint NOT NULL,
		    raw_model text NOT NULL,
		    canonical_id integer,
		    billing_mode text,
		    unit_price_in_per_1m numeric(10,4),
		    unit_price_out_per_1m numeric(10,4),
		    context_window integer,
		    success_rate numeric(5,4),
		    p95_latency_ms integer,
		    active_sessions integer DEFAULT 0,
		    concurrency_limit integer,
		    pressure_ratio numeric(5,4),
		    score_smart numeric(8,4),
		    score_speed_first numeric(8,4),
		    score_cost_first numeric(8,4),
		    updated_at timestamp with time zone DEFAULT now()
		) PARTITION BY RANGE (bucket);

		-- Indexes on archive table
		CREATE INDEX IF NOT EXISTS idx_cmi_archive_bucket 
		    ON credential_model_index_archive (bucket DESC);
		CREATE INDEX IF NOT EXISTS idx_cmi_archive_cred_model 
		    ON credential_model_index_archive (credential_id, raw_model, bucket DESC);
		CREATE INDEX IF NOT EXISTS idx_cmi_archive_canonical 
		    ON credential_model_index_archive (canonical_id, bucket DESC) 
		    WHERE canonical_id IS NOT NULL;
	`)
	if err != nil {
		return err
	}

	// archive_credential_model_index: archives data older than 7 days from main table
	// to columnar partition for the given month. Deletes archived rows from main table.
	_, err = d.pool.Exec(ctx, `
		CREATE OR REPLACE FUNCTION public.archive_credential_model_index(archive_month date)
		    RETURNS TABLE(status text, rows_archived bigint, rows_deleted bigint)
		    LANGUAGE plpgsql
		    AS $func$
		DECLARE
		    month_start date := date_trunc('month', archive_month)::date;
		    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
		    partition_name text := 'credential_model_index_archive_' || to_char(month_start, 'YYYY_MM');
		    archived_count bigint;
		    deleted_count bigint;
		    cutoff_ts timestamptz := NOW() - INTERVAL '7 days';
		BEGIN
		    -- Create target columnar partition if missing
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF credential_model_index_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            partition_name, month_start, month_end
		        );
		    END IF;

		    -- Archive 7d+ data for this month to columnar
		    INSERT INTO credential_model_index_archive
		    SELECT * FROM credential_model_index
		    WHERE bucket >= month_start 
		      AND bucket < month_end
		      AND bucket < cutoff_ts
		    ON CONFLICT DO NOTHING;
		    
		    GET DIAGNOSTICS archived_count = ROW_COUNT;

		    -- Delete archived data from main table
		    DELETE FROM credential_model_index
		    WHERE bucket >= month_start 
		      AND bucket < month_end
		      AND bucket < cutoff_ts;
		    
		    GET DIAGNOSTICS deleted_count = ROW_COUNT;

		    RETURN QUERY SELECT 'success'::text, archived_count, deleted_count;
		END;
		$func$;
	`)
	if err != nil {
		return err
	}

	// cleanup_old_credential_model_index: daily cleanup function. Removes data
	// older than 7 days from main table (assumes it has been archived).
	_, err = d.pool.Exec(ctx, `
		CREATE OR REPLACE FUNCTION public.cleanup_old_credential_model_index()
		    RETURNS bigint
		    LANGUAGE plpgsql
		    AS $func$
		DECLARE
		    deleted_count bigint;
		    cutoff_ts timestamptz := NOW() - INTERVAL '7 days';
		BEGIN
		    DELETE FROM credential_model_index
		    WHERE bucket < cutoff_ts;
		    
		    GET DIAGNOSTICS deleted_count = ROW_COUNT;
		    
		    RETURN deleted_count;
		END;
		$func$;
	`)
	if err != nil {
		return err
	}

	// ensure_next_month_cmi_archive_partition: pre-creates next month columnar
	// partition so archive_credential_model_index has a destination ready.
	_, err = d.pool.Exec(ctx, `
		CREATE OR REPLACE FUNCTION public.ensure_next_month_cmi_archive_partition()
		    RETURNS void
		    LANGUAGE plpgsql
		    AS $func$
		DECLARE
		    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
		    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
		    partition_name   text := 'credential_model_index_archive_' || to_char(next_month_start, 'YYYY_MM');
		BEGIN
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF credential_model_index_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            partition_name, next_month_start, next_month_end
		        );
		    END IF;
		END;
		$func$;
	`)
	if err != nil {
		return err
	}

	slog.Info("credential_model_index_archive schema ensured (parent heap + 3 helper functions)")
	return nil
}
