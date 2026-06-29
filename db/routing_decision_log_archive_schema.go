package db

import (
	"context"
	"log/slog"
)

// EnsureRoutingDecisionLogArchive ensures the routing_decision_log_archive tiered-storage
// parent table exists with the same schema as routing_decision_log.
//
// On first boot, the table is created along with the helper functions:
//  - archive_routing_decision_log(month date) - migrates one heap month to columnar
//  - ensure_next_month_routing_archive_partition() - pre-creates next month partition
//  - create_next_month_routing_partitions() - creates both heap and columnar partitions
//
// All DDL is idempotent: CREATE TABLE IF NOT EXISTS, CREATE OR REPLACE FUNCTION.
//
// After this ensure runs:
//  - public.routing_decision_log_archive (heap parent, RANGE by ts)
//  - Helper functions for archival and partition management
//  - RLS policy tenant_isolation_routing_decision_log_archive
//
// See deploy/sql/migrations/921_routing_decision_log_archive.sql for the standalone
// migration that does the same thing from psql.
func (d *DB) EnsureRoutingDecisionLogArchive(ctx context.Context) error {
	if d == nil || d.pool == nil {
		return nil
	}
	_, err := d.pool.Exec(ctx, `
		-- routing_decision_log_archive parent table (heap, RANGE by ts).
		-- Mirrors routing_decision_log schema. Historical (columnar) data is appended
		-- via archive_routing_decision_log(); updates never reach this tier.
		CREATE TABLE IF NOT EXISTS public.routing_decision_log_archive (
		    ts timestamp with time zone DEFAULT now() NOT NULL,
		    request_id uuid NOT NULL,
		    idempotency_key text,
		    tenant_id text,
		    api_key_id bigint,
		    model text NOT NULL,
		    chosen_credential_id bigint,
		    chosen_provider_id bigint,
		    tier smallint,
		    candidates_tried smallint,
		    latency_ms integer,
		    success boolean NOT NULL,
		    error_class text,
		    prompt_tokens integer,
		    completion_tokens integer,
		    cost_usd numeric(12,6),
		    request_bytes integer,
		    response_bytes integer,
		    client_model text,
		    resolved_raw_model text,
		    sticky_hit boolean,
		    client_profile text,
		    outbound_model text,
		    request_mode text,
		    identity_hash text,
		    transform_rule_id text,
		    egress_protocol text,
		    failure_stage text,
		    failure_detail_code text,
		    virtual_client_id text,
		    virtual_ip text,
		    virtual_mac text,
		    resolution_path text,
		    canonical_model text,
		    resolution_raw_models jsonb,
		    decision_trace jsonb
		) PARTITION BY RANGE (ts);

		-- RLS policy (mirrors routing_decision_log tenant isolation).
		ALTER TABLE public.routing_decision_log_archive ENABLE ROW LEVEL SECURITY;
		DROP POLICY IF EXISTS tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive;
		CREATE POLICY tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive
		    USING ((tenant_id)::text = (public.get_current_tenant())::text);
	`)
	if err != nil {
		return err
	}

	// archive_routing_decision_log: migrate one month of heap data into a columnar
	// partition and drop the source. Idempotent on both destination and source side.
	_, err = d.pool.Exec(ctx, `
		CREATE OR REPLACE FUNCTION public.archive_routing_decision_log(archive_month date)
		    RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
		    LANGUAGE plpgsql
		    AS $func$
		DECLARE
		    month_start date := date_trunc('month', archive_month)::date;
		    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
		    src_part    text := 'routing_decision_log_' || to_char(month_start, 'YYYY_MM');
		    dst_part    text := 'routing_decision_log_archive_' || to_char(month_start, 'YYYY_MM');
		    row_count   bigint;
		    col_list    text;
		BEGIN
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN
		        RETURN QUERY SELECT 'skipped'::text, 0::bigint, false;
		        RETURN;
		    END IF;

		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF routing_decision_log_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            dst_part, month_start, month_end
		        );
		    END IF;

		    SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position)
		    INTO col_list
		    FROM information_schema.columns a
		    JOIN information_schema.columns r
		      ON a.table_schema = r.table_schema
		     AND a.column_name  = r.column_name
		    WHERE a.table_name = 'routing_decision_log_archive'
		      AND r.table_name = src_part
		      AND a.table_schema = 'public'
		      AND a.ordinal_position > 0;

		    IF col_list IS NULL OR length(col_list) = 0 THEN
		        RAISE EXCEPTION 'No common columns between % and routing_decision_log_archive', src_part;
		    END IF;

		    EXECUTE format(
		        'INSERT INTO %I (%s) SELECT %s FROM %I',
		        dst_part, col_list, col_list, src_part
		    );
		    GET DIAGNOSTICS row_count = ROW_COUNT;

		    EXECUTE format('ALTER TABLE routing_decision_log DETACH PARTITION %I', src_part);
		    EXECUTE format('DROP TABLE %I', src_part);

		    RETURN QUERY SELECT 'success'::text, row_count, true;
		END;
		$func$;
	`)
	if err != nil {
		return err
	}

	// ensure_next_month_routing_archive_partition: cron helper. Pre-creates
	// next month columnar partition so archive_routing_decision_log has a
	// destination at month-end. Idempotent.
	_, err = d.pool.Exec(ctx, `
		CREATE OR REPLACE FUNCTION public.ensure_next_month_routing_archive_partition()
		    RETURNS void
		    LANGUAGE plpgsql
		    AS $func$
		DECLARE
		    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
		    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
		    partition_name   text := 'routing_decision_log_archive_' || to_char(next_month_start, 'YYYY_MM');
		BEGIN
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF routing_decision_log_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            partition_name, next_month_start, next_month_end
		        );
		    END IF;
		END;
		$func$;
	`)
	if err != nil {
		return err
	}

	// create_next_month_routing_partitions: creates both heap partition (main table)
	// and columnar partition (archive table) for next month. Unified helper.
	_, err = d.pool.Exec(ctx, `
		CREATE OR REPLACE FUNCTION public.create_next_month_routing_partitions()
		    RETURNS void
		    LANGUAGE plpgsql
		    AS $func$
		DECLARE
		    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
		    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
		    month_suffix     text := to_char(next_month_start, 'YYYY_MM');
		    partition_name   text := 'routing_decision_log_' || month_suffix;
		BEGIN
		    -- Create main table heap partition
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF routing_decision_log FOR VALUES FROM (%L) TO (%L) USING heap',
		            partition_name, next_month_start, next_month_end
		        );
		    END IF;
		    
		    -- Create archive table columnar partition
		    PERFORM ensure_next_month_routing_archive_partition();
		END;
		$func$;
	`)
	if err != nil {
		return err
	}

	slog.Info("routing_decision_log_archive schema ensured (parent heap + RLS + 3 helper functions)")
	return nil
}
