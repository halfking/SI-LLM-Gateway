--
-- PostgreSQL database dump
--

\restrict 4ey3UQUuyKB95a0ZOSRup1DCQroXHnLJZhA7aKDSzpkTqeL56r6HaeBBbwhY9qo

-- Dumped from database version 15.3 (Debian 15.3-1.pgdg120+1)
-- Dumped by pg_dump version 15.18 (Debian 15.18-1.pgdg12+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: citus_columnar; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS citus_columnar WITH SCHEMA pg_catalog;


--
-- Name: btree_gist; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS btree_gist WITH SCHEMA public;


--
-- Name: pg_trgm; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA public;


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: archive_credential_model_index(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_credential_model_index(archive_month date) RETURNS TABLE(status text, rows_archived bigint, rows_deleted bigint)
    LANGUAGE plpgsql
    AS $$
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
		$$;


--
-- Name: archive_request_logs(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_request_logs(archive_month date) RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    month_start date := date_trunc('month', archive_month)::date;
		    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
		    src_part    text := 'request_logs_' || to_char(month_start, 'YYYY_MM');
		    dst_part    text := 'request_logs_archive_' || to_char(month_start, 'YYYY_MM');
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
		            'CREATE TABLE %I PARTITION OF request_logs_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            dst_part, month_start, month_end
		        );
		    END IF;

		    SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position)
		    INTO col_list
		    FROM information_schema.columns a
		    JOIN information_schema.columns r
		      ON a.table_schema = r.table_schema
		     AND a.column_name  = r.column_name
		    WHERE a.table_name = 'request_logs_archive'
		      AND r.table_name = src_part
		      AND a.table_schema = 'public'
		      AND a.ordinal_position > 0;

		    IF col_list IS NULL OR length(col_list) = 0 THEN
		        RAISE EXCEPTION 'No common columns between % and request_logs_archive', src_part;
		    END IF;

		    EXECUTE format(
		        'INSERT INTO %I (%s) SELECT %s FROM %I',
		        dst_part, col_list, col_list, src_part
		    );
		    GET DIAGNOSTICS row_count = ROW_COUNT;

		    EXECUTE format('ALTER TABLE request_logs DETACH PARTITION %I', src_part);
		    EXECUTE format('DROP TABLE %I', src_part);

		    RETURN QUERY SELECT 'success'::text, row_count, true;
		END;
		$$;


--
-- Name: archive_request_wal(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_request_wal(archive_month date) RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
    AS $$ DECLARE month_start date := date_trunc('month', archive_month)::date; month_end date := (date_trunc('month', archive_month) + interval '1 month')::date; src_part text := 'request_wal_' || to_char(month_start, 'YYYY_MM'); dst_part text := 'request_wal_archive_' || to_char(month_start, 'YYYY_MM'); row_count bigint; partition_existed boolean := false; col_list text; BEGIN IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN RETURN QUERY SELECT 'skipped'::text, 0::bigint, false; RETURN; END IF; partition_existed := true; IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN EXECUTE format('CREATE TABLE %I PARTITION OF request_wal_archive FOR VALUES FROM (%L) TO (%L) USING columnar', dst_part, month_start, month_end); END IF; SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position) INTO col_list FROM information_schema.columns a JOIN information_schema.columns r ON a.table_schema = r.table_schema AND a.column_name = r.column_name WHERE a.table_name = 'request_wal_archive' AND r.table_name = src_part AND a.table_schema = 'public' AND a.ordinal_position > 0; IF col_list IS NULL OR length(col_list) = 0 THEN RAISE EXCEPTION 'No common columns between % and request_wal_archive', src_part; END IF; EXECUTE format('INSERT INTO %I (%s) SELECT %s FROM %I', dst_part, col_list, col_list, src_part); GET DIAGNOSTICS row_count = ROW_COUNT; EXECUTE format('ALTER TABLE request_wal DETACH PARTITION %I', src_part); EXECUTE format('DROP TABLE %I', src_part); RETURN QUERY SELECT 'success'::text, row_count, partition_existed; END; $$;


--
-- Name: archive_routing_decision_log(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_routing_decision_log(archive_month date) RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
    AS $$
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
		$$;


--
-- Name: array_unique_append(text[], text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.array_unique_append(arr text[], new_elem text) RETURNS text[]
    LANGUAGE plpgsql IMMUTABLE
    AS $$ BEGIN IF new_elem IS NULL THEN RETURN arr; END IF; IF new_elem = ANY(arr) THEN RETURN arr; ELSE RETURN array_append(arr, new_elem); END IF; END; $$;


--
-- Name: auto_set_fp_slot_limit(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.auto_set_fp_slot_limit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Auto-fill fp_slot_limit from concurrency_limit if not explicitly set
    IF NEW.fp_slot_limit IS NULL THEN
        IF NEW.concurrency_limit IS NOT NULL AND NEW.concurrency_limit > 0 THEN
            NEW.fp_slot_limit := GREATEST(1, NEW.concurrency_limit / 4);
        ELSE
            NEW.fp_slot_limit := 20;  -- 2026-06-24: 5→20, matches DefaultDefaultLimit
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: check_credential_dates(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.check_credential_dates() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF NEW.effective_at IS NOT NULL AND NEW.expires_at IS NOT NULL THEN
        IF NEW.expires_at <= NEW.effective_at THEN
            RAISE EXCEPTION 'expires_at must be greater than effective_at';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: cleanup_old_credential_model_index(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_old_credential_model_index() RETURNS bigint
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    deleted_count bigint;
		    cutoff_ts timestamptz := NOW() - INTERVAL '7 days';
		BEGIN
		    DELETE FROM credential_model_index
		    WHERE bucket < cutoff_ts;
		    
		    GET DIAGNOSTICS deleted_count = ROW_COUNT;
		    
		    RETURN deleted_count;
		END;
		$$;


--
-- Name: create_next_month_partitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_next_month_partitions() RETURNS text
    LANGUAGE plpgsql
    AS $$
DECLARE
    next_month_start date;
    next_month_end date;
    month_suffix text;
    result text := '';
BEGIN
    next_month_start := date_trunc('month', now() + interval '1 month');
    next_month_end := date_trunc('month', now() + interval '2 months');
    month_suffix := to_char(next_month_start, 'YYYY_MM');
    
    -- usage_ledger
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS usage_ledger_%s
        PARTITION OF usage_ledger
        FOR VALUES FROM (%L) TO (%L)
        USING heap',
        month_suffix, next_month_start, next_month_end);
    result := result || 'usage_ledger_' || month_suffix || ', ';
    
    -- credit_ledger
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS credit_ledger_%s
        PARTITION OF credit_ledger
        FOR VALUES FROM (%L) TO (%L)
        USING heap',
        month_suffix, next_month_start, next_month_end);
    result := result || 'credit_ledger_' || month_suffix || ', ';
    
    -- tool_usage_stats
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS tool_usage_stats_%s
        PARTITION OF tool_usage_stats
        FOR VALUES FROM (%L) TO (%L)
        USING heap',
        month_suffix, next_month_start, next_month_end);
    result := result || 'tool_usage_stats_' || month_suffix || ', ';
    
    -- request_logs
    EXECUTE format('
        CREATE TABLE IF NOT EXISTS request_logs_%s
        PARTITION OF request_logs
        FOR VALUES FROM (%L) TO (%L)
        USING heap',
        month_suffix, next_month_start, next_month_end);
    result := result || 'request_logs_' || month_suffix;
    
    RETURN '✅ Created partitions for ' || month_suffix || ': ' || result;
END;
$$;


--
-- Name: create_next_month_routing_partitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_next_month_routing_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
		$$;


--
-- Name: ensure_next_month_archive_partition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_next_month_archive_partition() RETURNS void
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
		    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
		    partition_name   text := 'request_logs_archive_' || to_char(next_month_start, 'YYYY_MM');
		BEGIN
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF request_logs_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            partition_name, next_month_start, next_month_end
		        );
		    END IF;
		END;
		$$;


--
-- Name: ensure_next_month_cmi_archive_partition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_next_month_cmi_archive_partition() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
		$$;


--
-- Name: ensure_next_month_routing_archive_partition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_next_month_routing_archive_partition() RETURNS void
    LANGUAGE plpgsql
    AS $$
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
		$$;


--
-- Name: ensure_request_logs_partition(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_request_logs_partition(target_ts timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    month_start   date := date_trunc('month', target_ts)::date;
    month_end     date := (date_trunc('month', target_ts) + interval '1 month')::date;
    part_name     text := 'request_logs_' || to_char(month_start, 'YYYY_MM');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = part_name) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF request_logs FOR VALUES FROM (%L) TO (%L)',
            part_name, month_start, month_end
        );
        EXECUTE format(
            'CREATE INDEX idx_%s_search_trgm ON %I USING gin (search_text gin_trgm_ops)',
            part_name, part_name
        );
        -- 2026-06-24 (migration 043): GIN trgm on client_model so the
        -- /api/logs ?model= ILIKE filter can use a bitmap index scan
        -- instead of a partition Seq Scan once volume grows.
        EXECUTE format(
            'CREATE INDEX idx_%s_client_model_trgm ON %I USING gin (client_model gin_trgm_ops)',
            part_name, part_name
        );
    END IF;
END;
$$;


--
-- Name: ensure_request_wal_partition(timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_request_wal_partition(target_ts timestamp with time zone DEFAULT now()) RETURNS void
    LANGUAGE plpgsql
    AS $$ DECLARE month_start date := date_trunc('month', target_ts)::date; month_end date := (date_trunc('month', target_ts) + interval '1 month')::date; part_name text := 'request_wal_' || to_char(month_start, 'YYYY_MM'); BEGIN IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = part_name AND relnamespace = 'public'::regnamespace) THEN EXECUTE format('CREATE TABLE %I PARTITION OF request_wal FOR VALUES FROM (%L) TO (%L)', part_name, month_start, month_end); END IF; END; $$;


--
-- Name: get_current_tenant(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_current_tenant() RETURNS text
    LANGUAGE sql STABLE
    AS $$ SELECT COALESCE(NULLIF(current_setting('app.current_tenant', true), ''), 'default'); $$;


--
-- Name: get_model_state_summary(text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_model_state_summary(p_raw_model_name text) RETURNS TABLE(state text, priority text, count bigint, avg_success_rate numeric, next_probe_in_seconds integer)
    LANGUAGE sql STABLE
    AS $$
		    SELECT
		        sub.state::TEXT,
		        sub.priority::TEXT,
		        COUNT(*) as count,
		        ROUND(AVG(CASE WHEN sub.total_attempts > 0
		                       THEN sub.consecutive_successes::float / sub.total_attempts * 100
		                       ELSE NULL END)::numeric, 2) as avg_success_rate,
		        EXTRACT(EPOCH FROM MIN(sub.next_retry_at - NOW()))::INTEGER as next_probe_in_seconds
		    FROM (
		        SELECT
		            mps.state,
		            mps.consecutive_successes,
		            mps.total_attempts,
		            mps.next_retry_at,
		            CASE
		                WHEN mps.consecutive_failures >= 3 THEN 'urgent'
		                WHEN mps.state = 'suspicious' THEN 'suspicious'
		                WHEN mps.state IN ('failing', 'recovering') THEN 'failing'
		                ELSE 'watchdog'
		            END as priority
		        FROM model_probe_state mps
		        JOIN credentials c ON c.id = mps.credential_id
		        WHERE mps.raw_model_name = p_raw_model_name
		          AND COALESCE(c.status, 'active') = 'active'
		          AND COALESCE(c.lifecycle_status, 'active') = 'active'
		          AND COALESCE(c.manual_disabled, FALSE) = FALSE
		    ) sub
		    GROUP BY sub.state, sub.priority
		    ORDER BY
		        CASE sub.priority
		            WHEN 'urgent' THEN 1
		            WHEN 'suspicious' THEN 2
		            WHEN 'failing' THEN 3
		            WHEN 'watchdog' THEN 4
		            ELSE 5
		        END,
		        sub.state;
		$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: prompt_injection_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_injection_policies (
    id integer NOT NULL,
    tenant_id character varying(255) NOT NULL,
    enabled boolean DEFAULT true,
    detection_mode character varying(20) DEFAULT 'observe'::character varying,
    enable_basic_rules boolean DEFAULT true,
    enable_advanced_rules boolean DEFAULT true,
    enable_heuristics boolean DEFAULT true,
    enable_ml_model boolean DEFAULT false,
    score_threshold_log integer DEFAULT 3,
    score_threshold_warn integer DEFAULT 6,
    score_threshold_sanitize integer DEFAULT 8,
    score_threshold_block integer DEFAULT 10,
    action_on_low_risk character varying(20) DEFAULT 'log'::character varying,
    action_on_medium_risk character varying(20) DEFAULT 'warn'::character varying,
    action_on_high_risk character varying(20) DEFAULT 'block'::character varying,
    whitelist_patterns text[],
    whitelist_users text[],
    notify_on_detection boolean DEFAULT false,
    notification_webhook character varying(500),
    notification_email character varying(255),
    total_detections integer DEFAULT 0,
    total_blocks integer DEFAULT 0,
    last_detection_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: get_prompt_injection_policy(character varying); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_prompt_injection_policy(p_tenant_id character varying) RETURNS public.prompt_injection_policies
    LANGUAGE plpgsql STABLE
    AS $$ DECLARE v_policy prompt_injection_policies; BEGIN SELECT * INTO v_policy FROM prompt_injection_policies WHERE tenant_id = p_tenant_id; RETURN v_policy; END; $$;


--
-- Name: key_applications_set_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.key_applications_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: model_offers_delete_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_offers_delete_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    UPDATE credential_model_bindings SET
        available = FALSE,
        unavailable_reason = 'deleted',
        admin_protected = FALSE,
        updated_at = now()
    WHERE id = OLD.id;
    RETURN OLD;
END;
$$;


--
-- Name: model_offers_insert_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_offers_insert_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO provider_models (provider_id, raw_model_name, canonical_id, outbound_model_name, available, last_seen_at)
    VALUES (
        (SELECT provider_id FROM credentials WHERE id = NEW.credential_id),
        NEW.raw_model_name,
        NEW.canonical_id,
        NEW.outbound_model_name,
        COALESCE(NEW.available, TRUE),
        COALESCE(NEW.last_seen_at, now())
    )
    ON CONFLICT (provider_id, raw_model_name) DO UPDATE SET
        canonical_id = COALESCE(EXCLUDED.canonical_id, provider_models.canonical_id),
        outbound_model_name = COALESCE(EXCLUDED.outbound_model_name, provider_models.outbound_model_name),
        last_seen_at = COALESCE(EXCLUDED.last_seen_at, provider_models.last_seen_at),
        available = TRUE,
        updated_at = now()
    RETURNING id INTO NEW.id;

    INSERT INTO credential_model_bindings (
        credential_id, provider_model_id, available,
        routing_tier, weight, manual_priority,
        success_rate, p95_latency_ms, active_sessions, consecutive_failures,
        unit_price_in_per_1m, unit_price_out_per_1m,
        cache_read_price_per_1m, cache_write_price_per_1m,
        currency, billing_mode, pricing_source, pricing_updated_at,
        admin_protected
    ) VALUES (
        NEW.credential_id, NEW.id, COALESCE(NEW.available, TRUE),
        COALESCE(NEW.routing_tier, 2), COALESCE(NEW.weight, 100), COALESCE(NEW.manual_priority, 99),
        COALESCE(NEW.success_rate, 0.9), COALESCE(NEW.p95_latency_ms, 0),
        COALESCE(NEW.active_sessions, 0), COALESCE(NEW.consecutive_failures, 0),
        COALESCE(NEW.unit_price_in_per_1m, 0), COALESCE(NEW.unit_price_out_per_1m, 0),
        COALESCE(NEW.cache_read_price_per_1m, 0), COALESCE(NEW.cache_write_price_per_1m, 0),
        COALESCE(NEW.currency, 'USD'), COALESCE(NEW.billing_mode, 'token'),
        NEW.pricing_source, NEW.pricing_updated_at,
        COALESCE(NEW.admin_protected, FALSE)
    )
    ON CONFLICT (credential_id, provider_model_id) DO UPDATE SET
        routing_tier = COALESCE(EXCLUDED.routing_tier, credential_model_bindings.routing_tier),
        weight = COALESCE(EXCLUDED.weight, credential_model_bindings.weight),
        manual_priority = COALESCE(EXCLUDED.manual_priority, credential_model_bindings.manual_priority),
        success_rate = COALESCE(EXCLUDED.success_rate, credential_model_bindings.success_rate),
        p95_latency_ms = COALESCE(EXCLUDED.p95_latency_ms, credential_model_bindings.p95_latency_ms),
        active_sessions = COALESCE(EXCLUDED.active_sessions, credential_model_bindings.active_sessions),
        consecutive_failures = COALESCE(EXCLUDED.consecutive_failures, credential_model_bindings.consecutive_failures),
        unit_price_in_per_1m = COALESCE(EXCLUDED.unit_price_in_per_1m, credential_model_bindings.unit_price_in_per_1m),
        unit_price_out_per_1m = COALESCE(EXCLUDED.unit_price_out_per_1m, credential_model_bindings.unit_price_out_per_1m),
        cache_read_price_per_1m = COALESCE(EXCLUDED.cache_read_price_per_1m, credential_model_bindings.cache_read_price_per_1m),
        cache_write_price_per_1m = COALESCE(EXCLUDED.cache_write_price_per_1m, credential_model_bindings.cache_write_price_per_1m),
        currency = COALESCE(EXCLUDED.currency, credential_model_bindings.currency),
        billing_mode = COALESCE(EXCLUDED.billing_mode, credential_model_bindings.billing_mode),
        pricing_source = COALESCE(EXCLUDED.pricing_source, credential_model_bindings.pricing_source),
        pricing_updated_at = COALESCE(EXCLUDED.pricing_updated_at, credential_model_bindings.pricing_updated_at),
        updated_at = now();

    RETURN NEW;
END;
$$;


--
-- Name: model_offers_update_trigger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_offers_update_trigger() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_pm_id BIGINT;
BEGIN
    SELECT provider_model_id INTO v_pm_id
    FROM credential_model_bindings WHERE id = OLD.id;

    IF v_pm_id IS NOT NULL THEN
        UPDATE provider_models SET
            canonical_id = COALESCE(NEW.canonical_id, provider_models.canonical_id),
            standardized_name = COALESCE(NEW.standardized_name, provider_models.standardized_name),
            outbound_model_name = COALESCE(NEW.outbound_model_name, provider_models.outbound_model_name),
            last_seen_at = COALESCE(NEW.last_seen_at, provider_models.last_seen_at),
            updated_at = now()
        WHERE id = v_pm_id;
    END IF;

    UPDATE credential_model_bindings SET
        available = COALESCE(NEW.available, credential_model_bindings.available),
        unavailable_reason = CASE
            WHEN NEW.unavailable_reason IS NOT NULL THEN NEW.unavailable_reason
            WHEN NEW.available IS NOT NULL AND NEW.available = TRUE THEN NULL
            ELSE credential_model_bindings.unavailable_reason
        END,
        unavailable_at = CASE
            WHEN NEW.unavailable_at IS NOT NULL THEN NEW.unavailable_at
            WHEN NEW.available IS NOT NULL AND NEW.available = TRUE THEN NULL
            ELSE credential_model_bindings.unavailable_at
        END,
        admin_protected = CASE
            WHEN NEW.admin_protected IS NOT NULL THEN NEW.admin_protected
            ELSE credential_model_bindings.admin_protected
        END,
        routing_tier = COALESCE(NEW.routing_tier, credential_model_bindings.routing_tier),
        weight = COALESCE(NEW.weight, credential_model_bindings.weight),
        manual_priority = COALESCE(NEW.manual_priority, credential_model_bindings.manual_priority),
        success_rate = COALESCE(NEW.success_rate, credential_model_bindings.success_rate),
        p95_latency_ms = COALESCE(NEW.p95_latency_ms, credential_model_bindings.p95_latency_ms),
        active_sessions = COALESCE(NEW.active_sessions, credential_model_bindings.active_sessions),
        consecutive_failures = COALESCE(NEW.consecutive_failures, credential_model_bindings.consecutive_failures),
        unit_price_in_per_1m = COALESCE(NEW.unit_price_in_per_1m, credential_model_bindings.unit_price_in_per_1m),
        unit_price_out_per_1m = COALESCE(NEW.unit_price_out_per_1m, credential_model_bindings.unit_price_out_per_1m),
        cache_read_price_per_1m = COALESCE(NEW.cache_read_price_per_1m, credential_model_bindings.cache_read_price_per_1m),
        cache_write_price_per_1m = COALESCE(NEW.cache_write_price_per_1m, credential_model_bindings.cache_write_price_per_1m),
        currency = COALESCE(NEW.currency, credential_model_bindings.currency),
        billing_mode = COALESCE(NEW.billing_mode, credential_model_bindings.billing_mode),
        pricing_source = COALESCE(NEW.pricing_source, credential_model_bindings.pricing_source),
        pricing_updated_at = COALESCE(NEW.pricing_updated_at, credential_model_bindings.pricing_updated_at),
        updated_at = now()
    WHERE id = OLD.id;

    RETURN NEW;
END;
$$;


--
-- Name: model_probe_backoff(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_backoff(consecutive_failures integer) RETURNS interval
    LANGUAGE sql IMMUTABLE
    AS $$
		    SELECT CASE
			WHEN consecutive_failures <= 0 THEN INTERVAL '30 seconds'
			WHEN consecutive_failures = 1  THEN INTERVAL '2 minutes'
			WHEN consecutive_failures = 2  THEN INTERVAL '5 minutes'
			ELSE                                  INTERVAL '15 minutes'
		    END;
		$$;


--
-- Name: model_probe_backoff_v2(integer, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_backoff_v2(consecutive_failures integer, last_attempt_at timestamp with time zone) RETURNS interval
    LANGUAGE sql IMMUTABLE
    AS $$
    WITH age AS (
        SELECT EXTRACT(EPOCH FROM (NOW() - COALESCE(last_attempt_at, NOW() - INTERVAL '1 hour'))) AS secs
    )
    SELECT CASE
        -- 0 failures → healthy_confirmed watchdog (every 2h)
        WHEN consecutive_failures <= 0 THEN INTERVAL '2 hours'

        -- 3+ failures → still recovering toward broken_confirmed
        WHEN consecutive_failures >= 3 THEN INTERVAL '60 minutes'

        -- 1 failure: ramp up frequency when fresh, taper when stale
        WHEN consecutive_failures = 1 AND (SELECT secs FROM age) <   300 THEN INTERVAL '1 minute'
        WHEN consecutive_failures = 1 AND (SELECT secs FROM age) <  1800 THEN INTERVAL '3 minutes'
        WHEN consecutive_failures = 1 AND (SELECT secs FROM age) <  3600 THEN INTERVAL '10 minutes'
        WHEN consecutive_failures = 1                              THEN INTERVAL '30 minutes'

        -- 2 failures: same pattern but with longer floor
        WHEN consecutive_failures = 2 AND (SELECT secs FROM age) <   300 THEN INTERVAL '2 minutes'
        WHEN consecutive_failures = 2 AND (SELECT secs FROM age) <  1800 THEN INTERVAL '5 minutes'
        WHEN consecutive_failures = 2 AND (SELECT secs FROM age) <  3600 THEN INTERVAL '15 minutes'
        WHEN consecutive_failures = 2                              THEN INTERVAL '45 minutes'

        -- 4+ failures: very rare, treat like 3+
        ELSE INTERVAL '60 minutes'
    END;
$$;


--
-- Name: model_probe_cleanup_stuck_probing(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_cleanup_stuck_probing() RETURNS integer
    LANGUAGE plpgsql
    AS $$ DECLARE cleaned_count INTEGER; BEGIN WITH cleaned AS (UPDATE model_probe_state SET state = 'suspicious', probing_started_at = NULL, next_retry_at = NOW() + INTERVAL '2 minutes' WHERE state = 'probing' AND probing_started_at IS NOT NULL AND probing_started_at < NOW() - INTERVAL '5 minutes' RETURNING 1) SELECT COUNT(*) INTO cleaned_count FROM cleaned; RETURN cleaned_count; END; $$;


--
-- Name: model_probe_credential_concurrency(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_credential_concurrency(p_credential_id bigint) RETURNS integer
    LANGUAGE sql STABLE
    AS $$ SELECT COUNT(*)::INTEGER FROM model_probe_state WHERE credential_id = p_credential_id AND state = 'probing' AND probing_started_at > NOW() - INTERVAL '5 minutes'; $$;


--
-- Name: model_probe_expire_to_suspicious(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_expire_to_suspicious() RETURNS integer
    LANGUAGE plpgsql
    AS $$ DECLARE expired_count INTEGER; BEGIN WITH updated AS (UPDATE model_probe_state SET state = 'suspicious', marked_suspicious_at = NOW(), state_expires_at = NULL, next_retry_at = NOW() WHERE state IN ('available', 'unavailable') AND state_expires_at IS NOT NULL AND state_expires_at <= NOW() RETURNING 1) SELECT COUNT(*) INTO expired_count FROM updated; RETURN expired_count; END; $$;


--
-- Name: model_probe_mark_available(bigint, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_mark_available(p_credential_id bigint, p_raw_model_name text, p_latency_ms integer DEFAULT 0) RETURNS void
    LANGUAGE plpgsql
    AS $$
		BEGIN
		    INSERT INTO model_probe_state
		        (credential_id, raw_model_name, state,
		         consecutive_successes, consecutive_failures,
		         last_attempt_at, next_retry_at, last_status,
		         state_expires_at, marked_suspicious_at)
		    VALUES
		        (p_credential_id, p_raw_model_name, 'available',
		         1, 0,
		         NOW(), NOW() + INTERVAL '2 hours', 'ok',
		         NOW() + INTERVAL '2 hours', NULL)
		    ON CONFLICT (credential_id, raw_model_name) DO UPDATE SET
		        state = 'available',
		        consecutive_successes = model_probe_state.consecutive_successes + 1,
		        consecutive_failures = 0,
		        last_attempt_at = NOW(),
		        next_retry_at = NOW() + INTERVAL '2 hours',
		        last_status = 'ok',
		        state_expires_at = NOW() + INTERVAL '2 hours',
		        marked_suspicious_at = NULL,
		        probing_started_at = NULL;

		    UPDATE credential_model_bindings cmb
		    SET available = TRUE,
		        unavailable_reason = NULL,
		        unavailable_at = NULL,
		        unavailable_recover_at = NULL,
		        updated_at = NOW()
		    FROM provider_models pm
		    WHERE cmb.provider_model_id = pm.id
		      AND cmb.credential_id = p_credential_id
		      AND pm.raw_model_name = p_raw_model_name
		      AND COALESCE(cmb.unavailable_reason, '') NOT LIKE 'manual%';
		END;
		$$;


--
-- Name: model_probe_mark_unavailable(bigint, text, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_mark_unavailable(p_credential_id bigint, p_raw_model_name text, p_error_code text, p_error_message text DEFAULT ''::text) RETURNS void
    LANGUAGE plpgsql
    AS $$
		BEGIN
		    INSERT INTO model_probe_state
		        (credential_id, raw_model_name, state,
		         consecutive_successes, consecutive_failures,
		         last_attempt_at, next_retry_at, last_status,
		         state_expires_at, marked_suspicious_at,
		         last_unavailable_reason, last_err_code)
		    VALUES
		        (p_credential_id, p_raw_model_name, 'unavailable',
		         0, 1,
		         NOW(), NOW() + INTERVAL '15 minutes', 'http_4xx',
		         NOW() + INTERVAL '15 minutes', NULL,
		         p_error_message, p_error_code)
		    ON CONFLICT (credential_id, raw_model_name) DO UPDATE SET
		        state = 'unavailable',
		        consecutive_successes = 0,
		        consecutive_failures = model_probe_state.consecutive_failures + 1,
		        last_attempt_at = NOW(),
		        next_retry_at = NOW() + INTERVAL '15 minutes',
		        last_status = 'http_4xx',
		        state_expires_at = NOW() + INTERVAL '15 minutes',
		        marked_suspicious_at = NULL,
		        probing_started_at = NULL,
		        last_unavailable_reason = p_error_message,
		        last_err_code = p_error_code;

		    UPDATE credential_model_bindings cmb
		    SET available = FALSE,
		        unavailable_reason = 'probe_' || p_error_code,
		        unavailable_at = NOW(),
		        unavailable_recover_at = NOW() + INTERVAL '15 minutes',
		        updated_at = NOW()
		    FROM provider_models pm
		    WHERE cmb.provider_model_id = pm.id
		      AND cmb.credential_id = p_credential_id
		      AND pm.raw_model_name = p_raw_model_name
		      AND COALESCE(cmb.unavailable_reason, '') NOT LIKE 'manual%';
		END;
		$$;


--
-- Name: model_probe_passive_boost(bigint, text, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_passive_boost(p_credential_id bigint, p_raw_model_name text, p_now timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    recent_count INTEGER;
    new_retry TIMESTAMPTZ;
BEGIN
    SELECT COUNT(*) INTO recent_count
    FROM candidate_failure_logs
    WHERE credential_id = p_credential_id
      AND raw_model_name = p_raw_model_name
      AND ts > p_now - INTERVAL '5 minutes';

    IF recent_count >= 3 THEN
        new_retry := p_now + INTERVAL '30 seconds';
    ELSIF recent_count >= 2 THEN
        new_retry := p_now + INTERVAL '1 minute';
    ELSE
        RETURN;
    END IF;

    UPDATE model_probe_state mps
    SET next_retry_at = LEAST(COALESCE(mps.next_retry_at, new_retry), new_retry)
    WHERE mps.credential_id = p_credential_id
      AND mps.raw_model_name = p_raw_model_name
      AND COALESCE(mps.state, 'unknown') <> 'broken_confirmed';
END;
$$;


--
-- Name: model_probe_reclaim_idle_slots(integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_reclaim_idle_slots(reclaim_after_seconds integer) RETURNS TABLE(deleted_slots integer, deleted_pins integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    v_deleted_slots INTEGER := 0;
    v_deleted_pins  INTEGER := 0;
    v_cutoff        TIMESTAMPTZ := NOW() - make_interval(secs => reclaim_after_seconds);
    rec             RECORD;
BEGIN
    -- Iterate over currently-occupied slots whose holder has been idle
    -- (no recent traffic on the holder identity) for longer than the
    -- cutoff. We use Redis-side expiration timestamps via the slot key
    -- TTL as the activity signal: a slot's TTL is refreshed on every
    -- Release(). If the TTL is below the cutoff, the holder has been
    -- idle since the last refresh.
    --
    -- We don't have direct access to Redis from plpgsql, so this SQL
    -- function targets the model_probe_state table (which mirrors the
    -- Redis slot via the runner's recordRun writes).
    --
    -- The Go goroutine in credentialfpslot handles the actual Redis
    -- DEL via the same Lua script used by ResetSlots. This SQL function
    -- is a companion for ops tooling and consistency checks.
    FOR rec IN
        SELECT credential_id, raw_model_name
        FROM model_probe_state
        WHERE last_attempt_at < v_cutoff
          AND state <> 'broken_confirmed'
    LOOP
        UPDATE model_probe_state
        SET state = 'unknown',
            consecutive_successes = 0,
            consecutive_failures = 0,
            next_retry_at = NOW() + INTERVAL '2 hours',
            -- do NOT change last_attempt_at — we want it to remain the
            -- "last activity" anchor for future audit queries.
            last_state_change_at = NOW()
        WHERE credential_id = rec.credential_id
          AND raw_model_name = rec.raw_model_name;
        v_deleted_slots := v_deleted_slots + 1;
    END LOOP;

    RETURN QUERY SELECT v_deleted_slots, v_deleted_pins;
END;
$$;


--
-- Name: model_probe_start_probing(bigint, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_start_probing(p_credential_id bigint, p_raw_model_name text, p_max_credential_concurrency integer DEFAULT 2) RETURNS boolean
    LANGUAGE plpgsql
    AS $$ DECLARE current_concurrency INTEGER; can_probe BOOLEAN := FALSE; BEGIN SELECT model_probe_credential_concurrency(p_credential_id) INTO current_concurrency; IF current_concurrency >= p_max_credential_concurrency THEN RETURN FALSE; END IF; WITH updated AS (UPDATE model_probe_state SET state = 'probing', probing_started_at = NOW(), last_attempt_at = NOW() WHERE credential_id = p_credential_id AND raw_model_name = p_raw_model_name AND state = 'suspicious' RETURNING 1) SELECT COUNT(*) > 0 INTO can_probe FROM updated; RETURN can_probe; END; $$;


--
-- Name: notify_auto_route_refresh(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.notify_auto_route_refresh() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE entity_id text := ''; BEGIN IF TG_TABLE_NAME = 'credential_model_bindings' THEN entity_id := COALESCE(NEW.credential_id, OLD.credential_id)::text; ELSIF TG_TABLE_NAME IN ('credentials', 'api_keys', 'providers') THEN entity_id := COALESCE(NEW.id, OLD.id)::text; END IF; PERFORM pg_notify('auto_route_refresh', TG_TABLE_NAME || ':' || TG_OP || ':' || entity_id); RETURN COALESCE(NEW, OLD); END; $$;


--
-- Name: recent_success_rate(bigint, text, integer, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.recent_success_rate(p_credential_id bigint, p_raw_model text, p_sample_n integer DEFAULT 50, p_window_hours integer DEFAULT 3) RETURNS TABLE(rate double precision, samples integer)
    LANGUAGE sql STABLE
    AS $$
		    WITH recent AS (
		        SELECT success
		        FROM request_logs
		        WHERE credential_id = p_credential_id
		          AND lower(COALESCE(outbound_model, client_model)) = lower(p_raw_model)
		          AND ts > NOW() - (p_window_hours || ' hours')::interval
		        ORDER BY ts DESC
		        LIMIT p_sample_n
		    )
		    SELECT AVG(CASE WHEN success THEN 1.0 ELSE 0.0 END)::double precision,
		           COUNT(*)::int
		    FROM recent;
		$$;


--
-- Name: routing_overrides_audit_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.routing_overrides_audit_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    v_actor TEXT := COALESCE(
		        NULLIF(current_setting('app.current_admin', true), ''),
		        'system'
		    );
		BEGIN
		    IF (TG_OP = 'INSERT') THEN
		        INSERT INTO routing_overrides_audit
		            (action, override_id, task_type, profile, mode,
		             model_chosen, reason, expires_at, actor)
		        VALUES
		            ('insert', NEW.id, NEW.task_type, NEW.profile, NEW.mode,
		             NEW.model_chosen, NEW.reason, NEW.expires_at, v_actor);
		        RETURN NEW;
		    ELSIF (TG_OP = 'UPDATE') THEN
		        IF NEW.expires_at IS DISTINCT FROM OLD.expires_at
		           OR NEW.reason IS DISTINCT FROM OLD.reason
		           OR NEW.model_chosen IS DISTINCT FROM OLD.model_chosen
		        THEN
		            INSERT INTO routing_overrides_audit
		                (action, override_id, task_type, profile, mode,
		                 model_chosen, reason, expires_at, old_expires_at,
		                 actor)
		            VALUES
		                ('update', NEW.id, NEW.task_type, NEW.profile, NEW.mode,
		                 NEW.model_chosen, NEW.reason, NEW.expires_at,
		                 OLD.expires_at, v_actor);
		        END IF;
		        RETURN NEW;
		    ELSIF (TG_OP = 'DELETE') THEN
		        INSERT INTO routing_overrides_audit
		            (action, override_id, task_type, profile, mode,
		             model_chosen, reason, expires_at, actor)
		        VALUES
		            ('delete', OLD.id, OLD.task_type, OLD.profile, OLD.mode,
		             OLD.model_chosen, OLD.reason, OLD.expires_at, v_actor);
		        RETURN OLD;
		    END IF;
		    RETURN NULL;
		END;
		$$;


--
-- Name: tenant_model_policies_audit_fn(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.tenant_model_policies_audit_fn() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    v_actor TEXT := COALESCE(
		        NULLIF(current_setting('app.current_admin', true), ''),
		        'system'
		    );
		BEGIN
		    IF (TG_OP = 'INSERT') THEN
		        INSERT INTO tenant_model_policies_audit
		            (action, policy_id, tenant_id, canonical_name, reason, actor)
		        VALUES
		            ('insert', NEW.id, NEW.tenant_id, NEW.canonical_name, NEW.reason, v_actor);
		        RETURN NEW;
		    ELSIF (TG_OP = 'UPDATE') THEN
		        IF NEW.deleted_at IS DISTINCT FROM OLD.deleted_at THEN
		            IF NEW.deleted_at IS NULL THEN
		                INSERT INTO tenant_model_policies_audit
		                    (action, policy_id, tenant_id, canonical_name, reason, actor)
		                VALUES
		                    ('undelete', NEW.id, NEW.tenant_id, NEW.canonical_name, NEW.reason, v_actor);
		            ELSE
		                INSERT INTO tenant_model_policies_audit
		                    (action, policy_id, tenant_id, canonical_name, reason, actor)
		                VALUES
		                    ('delete', NEW.id, NEW.tenant_id, NEW.canonical_name, OLD.reason, v_actor);
		            END IF;
		        ELSIF NEW.reason IS DISTINCT FROM OLD.reason
		              OR NEW.canonical_name IS DISTINCT FROM OLD.canonical_name
		        THEN
		            INSERT INTO tenant_model_policies_audit
		                (action, policy_id, tenant_id, canonical_name, reason, actor)
		            VALUES
		                ('update', NEW.id, NEW.tenant_id, NEW.canonical_name, NEW.reason, v_actor);
		        END IF;
		        RETURN NEW;
		    ELSIF (TG_OP = 'DELETE') THEN
		        INSERT INTO tenant_model_policies_audit
		            (action, policy_id, tenant_id, canonical_name, reason, actor)
		        VALUES
		            ('delete', OLD.id, OLD.tenant_id, OLD.canonical_name, OLD.reason, v_actor);
		        RETURN OLD;
		    END IF;
		    RETURN NULL;
		END;
		$$;


--
-- Name: trg_cmb_protect_manual_disable(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_cmb_protect_manual_disable() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF OLD.unavailable_reason = 'manual' THEN
        -- Admin explicit re-enable (toggleModelOfferState available=true)
        IF (NEW.available = TRUE AND NEW.unavailable_reason IS NULL)
           OR current_setting('llmgw.admin_override', true) = '1' THEN
            RETURN NEW;
        END IF;

        IF NEW.unavailable_reason IS DISTINCT FROM 'manual' THEN
            NEW.unavailable_reason := 'manual';
        END IF;
        IF NEW.available = TRUE THEN
            NEW.available := FALSE;
        END IF;
        IF NEW.unavailable_at IS NULL THEN
            NEW.unavailable_at := OLD.unavailable_at;
        END IF;
    END IF;
    RETURN NEW;
END;
$$;


--
-- Name: trg_session_audit_records_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.trg_session_audit_records_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;


--
-- Name: unified_probe_mark_failing(bigint, text, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unified_probe_mark_failing(p_credential_id bigint, p_raw_model_name text, p_error_code text, p_error_message text DEFAULT ''::text, p_retry_after_seconds integer DEFAULT 60) RETURNS void
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    current_failures INTEGER;
		    backoff_seconds INTEGER;
		BEGIN
		    SELECT COALESCE(consecutive_failures, 0) INTO current_failures
		    FROM model_probe_state
		    WHERE credential_id = p_credential_id
		      AND raw_model_name = p_raw_model_name;

		    backoff_seconds := LEAST(
		        p_retry_after_seconds * POWER(2, LEAST(current_failures, 6)),
		        3600
		    );

		    INSERT INTO model_probe_state
		        (credential_id, raw_model_name, state,
		         consecutive_successes, consecutive_failures,
		         last_attempt_at, next_retry_at,
		         probe_priority, last_status,
		         last_unavailable_reason, last_err_code,
		         probing_started_at, consecutive_watchdog_successes)
		    VALUES
		        (p_credential_id, p_raw_model_name, 'failing',
		         0, 1,
		         NOW(), NOW() + (backoff_seconds || ' seconds')::INTERVAL,
		         'failing', 'http_error',
		         p_error_message, p_error_code,
		         NULL, 0)
		    ON CONFLICT (credential_id, raw_model_name) DO UPDATE SET
		        state = 'failing',
		        consecutive_successes = 0,
		        consecutive_failures = model_probe_state.consecutive_failures + 1,
		        last_attempt_at = NOW(),
		        next_retry_at = NOW() + (backoff_seconds || ' seconds')::INTERVAL,
		        probe_priority = 'failing',
		        last_status = 'http_error',
		        last_unavailable_reason = p_error_message,
		        last_err_code = p_error_code,
		        probing_started_at = NULL,
		        consecutive_watchdog_successes = 0,
		        state_expires_at = NULL;

		    UPDATE credential_model_bindings cmb
		    SET available              = FALSE,
		        unavailable_reason     = 'probe_' || p_error_code,
		        unavailable_at         = NOW(),
		        unavailable_recover_at = NOW() + LEAST(backoff_seconds, 900) * INTERVAL '1 second',
		        updated_at             = NOW()
		    FROM provider_models pm
		    WHERE cmb.provider_model_id = pm.id
		      AND cmb.credential_id = p_credential_id
		      AND pm.raw_model_name = p_raw_model_name
		      AND COALESCE(cmb.unavailable_reason, '') NOT LIKE 'manual%';
		END;
		$$;


--
-- Name: unified_probe_mark_healthy(bigint, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.unified_probe_mark_healthy(p_credential_id bigint, p_raw_model_name text, p_latency_ms integer DEFAULT 0) RETURNS void
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    new_interval INTERVAL;
		BEGIN
		    SELECT CASE
		        WHEN consecutive_watchdog_successes >= 10 THEN '8 hours'::INTERVAL
		        WHEN consecutive_watchdog_successes >= 5 THEN '6 hours'::INTERVAL
		        WHEN consecutive_watchdog_successes >= 2 THEN '4 hours'::INTERVAL
		        ELSE '2 hours'::INTERVAL
		    END INTO new_interval
		    FROM model_probe_state
		    WHERE credential_id = p_credential_id
		      AND raw_model_name = p_raw_model_name;

		    INSERT INTO model_probe_state
		        (credential_id, raw_model_name, state,
		         consecutive_successes, consecutive_failures,
		         last_attempt_at, last_verified_at, next_retry_at,
		         probe_priority, verification_interval,
		         consecutive_watchdog_successes,
		         last_status, probing_started_at)
		    VALUES
		        (p_credential_id, p_raw_model_name, 'healthy',
		         1, 0,
		         NOW(), NOW(), NOW() + COALESCE(new_interval, '4 hours'::INTERVAL),
		         'watchdog', COALESCE(new_interval, '4 hours'::INTERVAL),
		         1,
		         'ok', NULL)
		    ON CONFLICT (credential_id, raw_model_name) DO UPDATE SET
		        state = 'healthy',
		        consecutive_successes = model_probe_state.consecutive_successes + 1,
		        consecutive_failures = 0,
		        last_attempt_at = NOW(),
		        last_verified_at = NOW(),
		        next_retry_at = NOW() + COALESCE(new_interval, model_probe_state.verification_interval, '4 hours'::INTERVAL),
		        probe_priority = 'watchdog',
		        verification_interval = COALESCE(new_interval, model_probe_state.verification_interval),
		        consecutive_watchdog_successes = CASE
		            WHEN model_probe_state.probe_priority = 'watchdog' THEN model_probe_state.consecutive_watchdog_successes + 1
		            ELSE 1
		        END,
		        last_status = 'ok',
		        probing_started_at = NULL,
		        state_expires_at = NULL,
		        marked_suspicious_at = NULL;

		    UPDATE credential_model_bindings cmb
		    SET available = TRUE,
		        unavailable_reason = NULL,
		        unavailable_at = NULL,
		        unavailable_recover_at = NULL,
		        updated_at = NOW()
		    FROM provider_models pm
		    WHERE cmb.provider_model_id = pm.id
		      AND cmb.credential_id = p_credential_id
		      AND pm.raw_model_name = p_raw_model_name
		      AND COALESCE(cmb.unavailable_reason, '') NOT LIKE 'manual%';
		END;
		$$;


--
-- Name: update_api_key_model_cost(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_api_key_model_cost() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    bucket_ts TIMESTAMPTZ;
    key_id INT;
    limit_val INT;
BEGIN
    -- 计算 5min bucket（向下取整）
    bucket_ts := date_trunc('hour', NEW.ts)
                  + (FLOOR(EXTRACT(minute FROM NEW.ts) / 5) * INTERVAL '5 minutes');
    key_id := NEW.api_key_id;
    IF key_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- 查找 api_key 的 rate_limit_rpm（作为该 key 的并发近似上限）
    -- 注意：api_keys 表没有 concurrency_limit 列（已在 realtime-trigger SQL 中确认）。
    -- 用 rate_limit_rpm / 10 作为近似（假设平均请求耗时 6 秒）。
    SELECT COALESCE(rate_limit_rpm, 0) / 10 INTO limit_val
    FROM api_keys WHERE id = key_id;

    -- 增量更新（注意：不在这里累加 active_concurrent，因为 AFTER INSERT 只能加不能减。
    -- active_concurrent 由 customer_cost_view 通过 JOIN request_logs 实时计算）
    INSERT INTO api_key_model_cost (
        bucket, api_key_id, canonical_id, raw_model, billing_mode,
        requests_total, requests_success,
        tokens_input, tokens_output, cost_usd,
        active_concurrent, concurrency_limit, pressure_ratio,
        last_request_at, updated_at
    ) VALUES (
        bucket_ts, key_id, NEW.canonical_id, COALESCE(NEW.outbound_model, NEW.client_model),
        'token',
        1, CASE WHEN NEW.success THEN 1 ELSE 0 END,
        COALESCE(NEW.prompt_tokens, 0), COALESCE(NEW.completion_tokens, 0),
        COALESCE(NEW.cost_usd, 0),
        1, limit_val,
        CASE WHEN limit_val > 0 THEN LEAST(1.0, 1.0 / limit_val) ELSE 0 END,
        NEW.ts, NOW()
    )
    ON CONFLICT (bucket, api_key_id, raw_model) DO UPDATE SET
        requests_total    = api_key_model_cost.requests_total + 1,
        requests_success  = api_key_model_cost.requests_success + CASE WHEN NEW.success THEN 1 ELSE 0 END,
        tokens_input      = api_key_model_cost.tokens_input + COALESCE(NEW.prompt_tokens, 0),
        tokens_output     = api_key_model_cost.tokens_output + COALESCE(NEW.completion_tokens, 0),
        cost_usd          = api_key_model_cost.cost_usd + COALESCE(NEW.cost_usd, 0),
        -- active_concurrent 在 trigger 中不更新（只在视图层动态计算）
        concurrency_limit = EXCLUDED.concurrency_limit,
        pressure_ratio    = CASE WHEN EXCLUDED.concurrency_limit > 0
                                  THEN LEAST(1.0, EXCLUDED.active_concurrent::numeric / EXCLUDED.concurrency_limit)
                                  ELSE 0 END,
        last_request_at   = NEW.ts,
        updated_at        = NOW();

    RETURN NEW;
END;
$$;


--
-- Name: update_provider_settings_updated_at(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_provider_settings_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;


--
-- Name: update_session_summary(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_session_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE v_input_cost DECIMAL(12,6); v_output_cost DECIMAL(12,6); v_total_cost DECIMAL(12,6); v_prompt_tokens BIGINT; v_completion_tokens BIGINT; v_latency_ms INT; v_status VARCHAR(50); v_client_model VARCHAR(100); v_upstream_model VARCHAR(100); v_work_type VARCHAR(50); v_provider VARCHAR(50); BEGIN v_input_cost := COALESCE(NEW.input_cost, 0); v_output_cost := COALESCE(NEW.output_cost, 0); v_total_cost := COALESCE(NEW.total_cost, 0); v_prompt_tokens := COALESCE(NEW.prompt_tokens, 0); v_completion_tokens := COALESCE(NEW.completion_tokens, 0); v_latency_ms := COALESCE(NEW.latency_ms, 0); v_status := NEW.status; v_client_model := NEW.client_model; v_upstream_model := NEW.upstream_model; v_work_type := NEW.work_type; v_provider := NEW.provider; INSERT INTO session_summaries (session_key, tenant_id, first_request_at, last_request_at, request_count, success_count, error_count, total_cost_usd, input_cost_usd, output_cost_usd, total_prompt_tokens, total_completion_tokens, avg_latency_ms, min_latency_ms, max_latency_ms, models_used, work_types, providers, client_models, updated_at) VALUES (NEW.session_key, NEW.tenant_id, NEW.created_at, NEW.created_at, 1, CASE WHEN v_status = 'success' THEN 1 ELSE 0 END, CASE WHEN v_status != 'success' THEN 1 ELSE 0 END, v_total_cost, v_input_cost, v_output_cost, v_prompt_tokens, v_completion_tokens, v_latency_ms, v_latency_ms, v_latency_ms, ARRAY[v_upstream_model]::TEXT[], CASE WHEN v_work_type IS NOT NULL THEN ARRAY[v_work_type]::TEXT[] ELSE '{}'::TEXT[] END, CASE WHEN v_provider IS NOT NULL THEN ARRAY[v_provider]::TEXT[] ELSE '{}'::TEXT[] END, CASE WHEN v_client_model IS NOT NULL THEN ARRAY[v_client_model]::TEXT[] ELSE '{}'::TEXT[] END, NOW()) ON CONFLICT (session_key) DO UPDATE SET last_request_at = GREATEST(session_summaries.last_request_at, NEW.created_at), request_count = session_summaries.request_count + 1, success_count = session_summaries.success_count + CASE WHEN v_status = 'success' THEN 1 ELSE 0 END, error_count = session_summaries.error_count + CASE WHEN v_status != 'success' THEN 1 ELSE 0 END, total_cost_usd = session_summaries.total_cost_usd + v_total_cost, input_cost_usd = session_summaries.input_cost_usd + v_input_cost, output_cost_usd = session_summaries.output_cost_usd + v_output_cost, total_prompt_tokens = session_summaries.total_prompt_tokens + v_prompt_tokens, total_completion_tokens = session_summaries.total_completion_tokens + v_completion_tokens, avg_latency_ms = ((session_summaries.avg_latency_ms * session_summaries.request_count + v_latency_ms) / (session_summaries.request_count + 1))::INT, min_latency_ms = LEAST(session_summaries.min_latency_ms, v_latency_ms), max_latency_ms = GREATEST(session_summaries.max_latency_ms, v_latency_ms), models_used = array_unique_append(session_summaries.models_used, v_upstream_model), work_types = array_unique_append(session_summaries.work_types, v_work_type), providers = array_unique_append(session_summaries.providers, v_provider), client_models = array_unique_append(session_summaries.client_models, v_client_model), updated_at = NOW(); RETURN NEW; END; $$;


--
-- Name: agent_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agent_relationships (
    src_agent_id bigint NOT NULL,
    dst_agent_id bigint NOT NULL,
    rel text NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_agent_rel CHECK ((rel = ANY (ARRAY['calls'::text, 'delegates'::text, 'depends_on'::text, 'similar_to'::text]))),
    CONSTRAINT chk_agent_rel_no_self CHECK ((src_agent_id <> dst_agent_id))
);


--
-- Name: agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.agents (
    id bigint NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    endpoint text NOT NULL,
    status text DEFAULT 'unknown'::text NOT NULL,
    capabilities jsonb DEFAULT '{}'::jsonb NOT NULL,
    version text DEFAULT '0.0.0'::text NOT NULL,
    auth_scheme text,
    last_heartbeat timestamp with time zone,
    registered_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_agents_auth CHECK (((auth_scheme IS NULL) OR (auth_scheme = ANY (ARRAY['bearer'::text, 'api_key'::text, 'mtls'::text, 'none'::text])))),
    CONSTRAINT chk_agents_kind CHECK ((kind = ANY (ARRAY['openclaw'::text, 'brandmind-go'::text, 'crm-go'::text, 'custom'::text]))),
    CONSTRAINT chk_agents_status CHECK ((status = ANY (ARRAY['healthy'::text, 'degraded'::text, 'down'::text, 'unknown'::text])))
);


--
-- Name: agents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.agents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: agents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.agents_id_seq OWNED BY public.agents.id;


--
-- Name: analysis_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.analysis_events (
    id bigint NOT NULL,
    event_id text NOT NULL,
    type text NOT NULL,
    tenant_id text NOT NULL,
    session_id text,
    request_id text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    worker text,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text
);


--
-- Name: analysis_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.analysis_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: analysis_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.analysis_events_id_seq OWNED BY public.analysis_events.id;


--
-- Name: api_key_auto_profile; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_key_auto_profile (
    api_key_id integer NOT NULL,
    profile text DEFAULT 'smart'::text NOT NULL,
    first_chosen_at timestamp with time zone DEFAULT now(),
    last_used_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT api_key_auto_profile_profile_check CHECK ((profile = ANY (ARRAY['smart'::text, 'speed_first'::text, 'cost_first'::text])))
);


--
-- Name: api_key_model_cost; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_key_model_cost (
    bucket timestamp with time zone NOT NULL,
    api_key_id integer NOT NULL,
    canonical_id integer,
    raw_model text NOT NULL,
    billing_mode text,
    requests_total integer DEFAULT 0 NOT NULL,
    requests_success integer DEFAULT 0 NOT NULL,
    tokens_input bigint DEFAULT 0 NOT NULL,
    tokens_output bigint DEFAULT 0 NOT NULL,
    cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    active_concurrent integer DEFAULT 0 NOT NULL,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    last_request_at timestamp with time zone,
    last_decision_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: api_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_keys (
    id bigint NOT NULL,
    application_id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    key_hash text NOT NULL,
    key_prefix text NOT NULL,
    owner_user text,
    data_sensitivity text DEFAULT 'internal'::text NOT NULL,
    default_end_user_id text,
    budget_usd numeric(14,6),
    rate_limit_rpm integer,
    enabled boolean DEFAULT true NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    status character varying(16) DEFAULT 'active'::character varying NOT NULL,
    key_ciphertext text,
    is_system boolean DEFAULT false NOT NULL,
    rate_limit_concurrent integer,
    rate_limit_tpm integer,
    key_tier character varying(16) DEFAULT 'default'::character varying NOT NULL,
    key_ciphertext_kid text,
    throttled_at timestamp with time zone,
    throttled_reason text,
    ewma_rpm_baseline numeric(10,3),
    ewma_updated_at timestamp with time zone,
    reveal_count integer DEFAULT 0 NOT NULL,
    last_revealed_at timestamp with time zone,
    last_revealed_by text,
    remark text,
    key_alias text,
    total_requests bigint DEFAULT 0 NOT NULL,
    total_prompt_tokens bigint DEFAULT 0 NOT NULL,
    total_completion_tokens bigint DEFAULT 0 NOT NULL,
    total_tokens bigint DEFAULT 0 NOT NULL,
    total_cost_usd numeric(14,8) DEFAULT 0 NOT NULL,
    last_request_at timestamp with time zone,
    default_client_profile text,
    CONSTRAINT api_keys_data_sensitivity_check CHECK ((data_sensitivity = ANY (ARRAY['public'::text, 'internal'::text, 'confidential'::text]))),
    CONSTRAINT api_keys_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('pending'::character varying)::text, ('disabled'::character varying)::text, ('throttled'::character varying)::text, ('revoked'::character varying)::text])))
);


--
-- Name: api_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.api_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.api_keys_id_seq OWNED BY public.api_keys.id;


--
-- Name: applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.applications (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL,
    owner_user text,
    data_sensitivity text DEFAULT 'internal'::text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    default_client_profile text,
    allowed_models_json jsonb,
    CONSTRAINT applications_data_sensitivity_check CHECK ((data_sensitivity = ANY (ARRAY['public'::text, 'internal'::text, 'confidential'::text])))
);


--
-- Name: applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.applications_id_seq OWNED BY public.applications.id;


--
-- Name: approval_queue; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.approval_queue (
    id uuid NOT NULL,
    session_id text NOT NULL,
    tenant_id text NOT NULL,
    request_id text NOT NULL,
    detect_result jsonb NOT NULL,
    snapshot jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    approved_by text,
    approved_at timestamp with time zone,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT approval_queue_status_chk CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'timeout'::text])))
);

ALTER TABLE ONLY public.approval_queue FORCE ROW LEVEL SECURITY;


--
-- Name: armor_judgments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.armor_judgments (
    id bigint NOT NULL,
    request_id text NOT NULL,
    tenant_id text NOT NULL,
    check_type text NOT NULL,
    decision text NOT NULL,
    source text NOT NULL,
    pattern_ids text[],
    judge_model text,
    score real,
    threshold real,
    mode text DEFAULT 'observe'::text NOT NULL,
    latency_ms integer DEFAULT 0 NOT NULL,
    prompt_sha256 text,
    snippet text,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_armor_check CHECK ((check_type = ANY (ARRAY['prompt_inject'::text, 'pii'::text, 'hallucination'::text]))),
    CONSTRAINT chk_armor_decision CHECK ((decision = ANY (ARRAY['safe'::text, 'warn'::text, 'block'::text]))),
    CONSTRAINT chk_armor_mode CHECK ((mode = ANY (ARRAY['observe'::text, 'enforce'::text]))),
    CONSTRAINT chk_armor_source CHECK ((source = ANY (ARRAY['pattern'::text, 'judge'::text])))
);


--
-- Name: armor_judgments_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.armor_judgments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: armor_judgments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.armor_judgments_id_seq OWNED BY public.armor_judgments.id;


--
-- Name: asset_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.asset_relationships (
    src_kind text NOT NULL,
    src_ref_id bigint NOT NULL,
    dst_kind text NOT NULL,
    dst_ref_id bigint NOT NULL,
    rel text NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_asset_rel_type CHECK ((rel = ANY (ARRAY['depends_on'::text, 'calls'::text, 'similar_to'::text])))
);


--
-- Name: assets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.assets (
    kind text NOT NULL,
    ref_id bigint NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    owner text,
    team text,
    cost_center text,
    tags jsonb DEFAULT '{}'::jsonb NOT NULL,
    health_state text DEFAULT 'unknown'::text NOT NULL,
    version text DEFAULT '0.0.0'::text NOT NULL,
    registered_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_assets_health CHECK ((health_state = ANY (ARRAY['healthy'::text, 'degraded'::text, 'down'::text, 'unknown'::text]))),
    CONSTRAINT chk_assets_kind CHECK ((kind = ANY (ARRAY['llm_endpoint'::text, 'mcp_server'::text, 'agent'::text])))
);


--
-- Name: auto_tune_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auto_tune_audit (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    action text NOT NULL,
    old_limit integer,
    new_limit integer,
    reason text,
    peak_concurrent integer,
    p95_concurrent numeric(8,2),
    week_start timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    applied_by text
);


--
-- Name: auto_tune_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.auto_tune_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: auto_tune_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.auto_tune_audit_id_seq OWNED BY public.auto_tune_audit.id;


--
-- Name: background_tasks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.background_tasks (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    task_type text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    status text DEFAULT 'running'::text NOT NULL,
    request_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_json jsonb,
    error text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone
);


--
-- Name: background_tasks_duplicates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.background_tasks_duplicates (
    id bigint NOT NULL,
    tenant_id text NOT NULL,
    task_type text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    status text NOT NULL,
    request_json jsonb NOT NULL,
    result_json jsonb,
    error text,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    removed_at timestamp with time zone DEFAULT now()
);


--
-- Name: background_tasks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.background_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: background_tasks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.background_tasks_id_seq OWNED BY public.background_tasks.id;


--
-- Name: billing_orders; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.billing_orders (
    id bigint NOT NULL,
    order_no character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    order_type character varying(16) NOT NULL,
    status character varying(16) DEFAULT 'pending'::character varying NOT NULL,
    amount_cents integer NOT NULL,
    credits bigint NOT NULL,
    plan_id integer,
    package_id integer,
    payment_channel character varying(16) DEFAULT 'alipay'::character varying NOT NULL,
    qr_payload text DEFAULT ''::text NOT NULL,
    qr_url text DEFAULT ''::text NOT NULL,
    paid_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT billing_orders_order_type_check CHECK (((order_type)::text = ANY (ARRAY[('subscribe'::character varying)::text, ('topup'::character varying)::text]))),
    CONSTRAINT billing_orders_payment_channel_check CHECK (((payment_channel)::text = ANY (ARRAY[('alipay'::character varying)::text, ('wechat'::character varying)::text, ('manual'::character varying)::text]))),
    CONSTRAINT billing_orders_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('paid'::character varying)::text, ('cancelled'::character varying)::text, ('expired'::character varying)::text])))
);


--
-- Name: billing_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.billing_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: billing_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.billing_orders_id_seq OWNED BY public.billing_orders.id;


SET default_table_access_method = columnar;

--
-- Name: candidate_failure_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.candidate_failure_logs (
    id bigint,
    request_id text,
    ts timestamp with time zone,
    tenant_id text,
    credential_id integer,
    provider_id integer,
    raw_model_name text,
    attempt_index integer,
    error_kind text,
    error_message text,
    upstream_status_code integer,
    upstream_response_body text,
    upstream_response_preview text,
    latency_ms integer,
    retryable boolean,
    context jsonb,
    per_attempt_latency_ms integer
);


SET default_table_access_method = heap;

--
-- Name: credential_capabilities; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_capabilities (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    capability text NOT NULL,
    supported boolean DEFAULT false NOT NULL,
    last_tested_at timestamp with time zone,
    evidence_json jsonb,
    CONSTRAINT credential_capabilities_capability_check CHECK ((capability = ANY (ARRAY['tool_use'::text, 'vision'::text, 'streaming'::text, 'prompt_caching'::text, 'structured_output'::text, 'long_context'::text, 'json_mode'::text, 'batch'::text])))
);


--
-- Name: credential_capabilities_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credential_capabilities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_capabilities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credential_capabilities_id_seq OWNED BY public.credential_capabilities.id;


--
-- Name: credential_health_checks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_health_checks (
    id bigint NOT NULL,
    run_id bigint,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    provider_id bigint NOT NULL,
    credential_id bigint NOT NULL,
    models_ok boolean DEFAULT false NOT NULL,
    probe_ok boolean DEFAULT false NOT NULL,
    health_status text NOT NULL,
    warning_code text,
    classification_reason text,
    models_failure_reason text,
    models_http_status integer,
    probe_http_status integer,
    models_latency_ms integer,
    probe_latency_ms integer,
    probe_model text,
    models_error text,
    probe_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_credential_health_checks_models_failure_reason CHECK (((models_failure_reason IS NULL) OR (models_failure_reason = ANY (ARRAY['request_failed'::text, 'empty_models'::text, 'invalid_payload'::text, 'not_supported'::text])))),
    CONSTRAINT chk_credential_health_checks_status CHECK ((health_status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'warning'::text, 'unreachable'::text])))
);


--
-- Name: credential_health_checks_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credential_health_checks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_health_checks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credential_health_checks_id_seq OWNED BY public.credential_health_checks.id;


--
-- Name: credential_model_bindings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_bindings (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    provider_model_id bigint NOT NULL,
    routing_tier smallint DEFAULT 2,
    weight smallint DEFAULT 100,
    manual_priority smallint DEFAULT 99,
    success_rate numeric,
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    consecutive_failures integer DEFAULT 0,
    unit_price_in_per_1m numeric,
    unit_price_out_per_1m numeric,
    cache_read_price_per_1m numeric,
    cache_write_price_per_1m numeric,
    currency text DEFAULT 'USD'::text,
    billing_mode text DEFAULT 'per_token'::text,
    pricing_source text,
    pricing_updated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    available boolean DEFAULT true NOT NULL,
    unavailable_reason text,
    unavailable_at timestamp with time zone,
    plan_meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    admin_protected boolean DEFAULT false NOT NULL,
    unavailable_recover_at timestamp with time zone
);


--
-- Name: credential_model_bindings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credential_model_bindings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_model_bindings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credential_model_bindings_id_seq OWNED BY public.credential_model_bindings.id;


--
-- Name: credential_model_call_history; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_call_history (
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    window_start timestamp with time zone NOT NULL,
    total_calls integer DEFAULT 0 NOT NULL,
    success_calls integer DEFAULT 0 NOT NULL,
    failed_calls integer DEFAULT 0 NOT NULL,
    avg_latency_ms numeric(8,2),
    p95_latency_ms integer,
    p99_latency_ms integer,
    error_rate_limit_count integer DEFAULT 0 NOT NULL,
    error_quota_count integer DEFAULT 0 NOT NULL,
    error_concurrent_count integer DEFAULT 0 NOT NULL,
    error_network_count integer DEFAULT 0 NOT NULL,
    error_auth_count integer DEFAULT 0 NOT NULL,
    error_other_count integer DEFAULT 0 NOT NULL,
    avg_concurrent numeric(5,2),
    peak_concurrent integer,
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: credential_model_index; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_index (
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
);


--
-- Name: credential_model_index_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_index_archive (
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
)
PARTITION BY RANGE (bucket);


SET default_table_access_method = columnar;

--
-- Name: credential_model_index_archive_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_index_archive_2026_06 (
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
);


SET default_table_access_method = heap;

--
-- Name: credential_model_peak_1m; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_peak_1m (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    peak_concurrent integer DEFAULT 0 NOT NULL,
    avg_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL
);


--
-- Name: credential_model_stats_1m; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_stats_1m (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    raw_model text DEFAULT ''::text NOT NULL,
    requests integer DEFAULT 0 NOT NULL,
    successes integer DEFAULT 0 NOT NULL,
    failures integer DEFAULT 0 NOT NULL,
    latency_p50_ms integer,
    latency_p95_ms integer,
    latency_p99_ms integer,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cost_usd numeric(14,8) DEFAULT 0 NOT NULL,
    error_counts jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
-- Name: credential_model_weekly_peak; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_weekly_peak (
    week_start timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    peak_concurrent integer DEFAULT 0 NOT NULL,
    peak_concurrent_5min integer DEFAULT 0 NOT NULL,
    p95_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    avg_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    total_requests bigint DEFAULT 0 NOT NULL,
    sample_days integer DEFAULT 0 NOT NULL,
    current_limit integer DEFAULT 0 NOT NULL,
    suggested_limit integer,
    suggestion_reason text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


SET default_table_access_method = columnar;

--
-- Name: credential_probe_model_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_probe_model_log (
    id bigint,
    tenant_id text,
    credential_id bigint,
    source text,
    old_model text,
    new_model text,
    actor text,
    reason text,
    created_at timestamp with time zone
);


SET default_table_access_method = heap;

--
-- Name: credential_quota_usage; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_quota_usage (
    id bigint NOT NULL,
    quota_id bigint NOT NULL,
    window_started_at timestamp with time zone NOT NULL,
    window_ends_at timestamp with time zone NOT NULL,
    used_total_tokens bigint DEFAULT 0 NOT NULL,
    used_input_tokens bigint DEFAULT 0 NOT NULL,
    used_output_tokens bigint DEFAULT 0 NOT NULL,
    used_requests bigint DEFAULT 0 NOT NULL,
    used_cost_usd numeric(18,8) DEFAULT 0 NOT NULL,
    last_event_at timestamp with time zone,
    exhausted boolean DEFAULT false NOT NULL
);


--
-- Name: credential_quota_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credential_quota_usage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_quota_usage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credential_quota_usage_id_seq OWNED BY public.credential_quota_usage.id;


--
-- Name: credential_quotas; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_quotas (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    quota_name text NOT NULL,
    window_type text NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    period text,
    cron_expr text,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    reset_anchor_local time without time zone,
    rolling_seconds integer,
    cap_total_tokens bigint,
    cap_input_tokens bigint,
    cap_output_tokens bigint,
    cap_requests bigint,
    cap_cost_usd numeric(14,6),
    unlimited_in_window boolean DEFAULT false NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT credential_quotas_window_type_check CHECK ((window_type = ANY (ARRAY['fixed'::text, 'recurring'::text, 'rolling'::text])))
);


--
-- Name: credential_quotas_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credential_quotas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credential_quotas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credential_quotas_id_seq OWNED BY public.credential_quotas.id;


--
-- Name: credentials; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credentials (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    label text NOT NULL,
    secret_ciphertext bytea,
    secret_kid text,
    trust_level text DEFAULT 'trusted'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    concurrency_limit integer,
    effective_concurrency integer,
    balance_usd numeric(14,6),
    pricing_distrust boolean DEFAULT false NOT NULL,
    relay_overhead_ms integer,
    active_plan_id bigint,
    plan_consumed_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    api_models_ok boolean,
    api_models_last_checked_at timestamp with time zone,
    api_models_error text,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    circuit_state text DEFAULT 'closed'::text,
    circuit_opened_at timestamp with time zone,
    consecutive_failures integer DEFAULT 0,
    cooling_until timestamp with time zone,
    circuit_open_count_window integer DEFAULT 0,
    circuit_window_started_at timestamp with time zone,
    effective_at timestamp with time zone,
    expires_at timestamp with time zone,
    tags jsonb DEFAULT '[]'::jsonb,
    notes text,
    health_status text DEFAULT 'unknown'::text NOT NULL,
    health_checked_at timestamp with time zone,
    health_source text,
    health_warning_code text,
    health_error text,
    health_latency_ms integer,
    health_probe_model text,
    lifecycle_status text DEFAULT 'active'::text NOT NULL,
    availability_state text DEFAULT 'ready'::text NOT NULL,
    quota_state text DEFAULT 'ok'::text NOT NULL,
    state_reason_code text,
    state_reason_detail text,
    state_updated_at timestamp with time zone,
    availability_recover_at timestamp with time zone,
    quota_recover_at timestamp with time zone,
    balance_currency text DEFAULT 'USD'::text,
    balance_last_checked_at timestamp with time zone,
    balance_check_endpoint text,
    pool_group text,
    acquisition_source text,
    acquisition_detail text,
    manual_disabled boolean DEFAULT false NOT NULL,
    default_probe_model text,
    default_probe_model_source text,
    default_probe_model_picked_at timestamp with time zone,
    concurrency_limit_auto integer,
    fp_slot_limit integer NOT NULL,
    CONSTRAINT chk_credentials_health_source CHECK (((health_source IS NULL) OR (health_source = ANY (ARRAY['models'::text, 'probe'::text, 'mixed'::text, 'none'::text, 'fast_reprobe'::text])))),
    CONSTRAINT chk_credentials_health_status CHECK ((health_status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'warning'::text, 'unreachable'::text]))),
    CONSTRAINT credentials_availability_state_check CHECK ((availability_state = ANY (ARRAY['ready'::text, 'cooling'::text, 'rate_limited'::text, 'auth_failed'::text, 'unreachable'::text, 'suspended'::text]))),
    CONSTRAINT credentials_circuit_state_chk CHECK ((circuit_state = ANY (ARRAY['closed'::text, 'open'::text, 'half_open'::text]))),
    CONSTRAINT credentials_fp_slot_limit_check CHECK (((fp_slot_limit >= 0) AND (fp_slot_limit <= 10000))),
    CONSTRAINT credentials_fp_slot_vs_concurrency CHECK (((concurrency_limit IS NULL) OR (fp_slot_limit IS NULL) OR (fp_slot_limit <= concurrency_limit))),
    CONSTRAINT credentials_lifecycle_status_check CHECK ((lifecycle_status = ANY (ARRAY['active'::text, 'disabled'::text, 'suspended'::text, 'retired'::text]))),
    CONSTRAINT credentials_status_check CHECK ((status = ANY (ARRAY['active'::text, 'cooling'::text, 'degraded'::text, 'quarantine'::text, 'quota_expired'::text, 'disabled'::text]))),
    CONSTRAINT credentials_trust_level_check CHECK ((trust_level = ANY (ARRAY['trusted'::text, 'cooling'::text, 'degraded'::text, 'quarantine'::text])))
);


--
-- Name: credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credentials_id_seq OWNED BY public.credentials.id;


--
-- Name: credit_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_ledger (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
)
PARTITION BY RANGE (created_at);


--
-- Name: credit_ledger_partitioned_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credit_ledger_partitioned_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credit_ledger_partitioned_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credit_ledger_partitioned_id_seq OWNED BY public.credit_ledger.id;


--
-- Name: credit_ledger_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_ledger_2026_06 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);


--
-- Name: credit_ledger_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_ledger_2026_07 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);


--
-- Name: credit_ledger_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_ledger_2026_08 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);


--
-- Name: credit_ledger_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_ledger_old (
    id bigint NOT NULL,
    tenant_id character varying(64) NOT NULL,
    entry_type character varying(32) NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying(32),
    ref_id character varying(128),
    note text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying(32),
    CONSTRAINT credit_ledger_entry_type_check CHECK (((entry_type)::text = ANY (ARRAY[('consume'::character varying)::text, ('topup'::character varying)::text, ('subscribe'::character varying)::text, ('adjust'::character varying)::text, ('refund'::character varying)::text])))
);


--
-- Name: credit_ledger_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.credit_ledger_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: credit_ledger_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.credit_ledger_id_seq OWNED BY public.credit_ledger_old.id;


--
-- Name: request_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.request_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: request_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
)
PARTITION BY RANGE (ts);

ALTER TABLE ONLY public.request_logs FORCE ROW LEVEL SECURITY;


--
-- Name: customer_cost_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.customer_cost_view AS
 SELECT akmc.api_key_id,
    ak.key_alias,
    ak.tenant_id,
    ak.application_id,
    sum(
        CASE
            WHEN (akmc.bucket >= (now() - '01:00:00'::interval)) THEN akmc.cost_usd
            ELSE (0)::numeric
        END) AS cost_usd_1h,
    sum(
        CASE
            WHEN (akmc.bucket >= (now() - '24:00:00'::interval)) THEN akmc.cost_usd
            ELSE (0)::numeric
        END) AS cost_usd_24h,
    sum(
        CASE
            WHEN (akmc.bucket >= (now() - '7 days'::interval)) THEN akmc.cost_usd
            ELSE (0)::numeric
        END) AS cost_usd_7d,
    sum(akmc.requests_total) AS total_auto_requests,
    sum(akmc.requests_success) AS total_auto_success,
    ( SELECT count(*) AS count
           FROM public.request_logs rl
          WHERE ((rl.api_key_id = akmc.api_key_id) AND (rl.is_auto_request = true) AND (rl.ts >= (now() - '00:05:00'::interval)) AND (rl.success IS NOT NULL) AND (rl.ts IS NOT NULL))) AS active_concurrent,
    max(akmc.concurrency_limit) AS concurrency_limit,
    avg(
        CASE
            WHEN (akmc.bucket >= (now() - '01:00:00'::interval)) THEN akmc.pressure_ratio
            ELSE NULL::numeric
        END) AS avg_pressure_1h,
    max(akmc.score_smart) AS best_score_smart,
    max(akmc.score_speed_first) AS best_score_speed_first,
    max(akmc.score_cost_first) AS best_score_cost_first,
    max(akmc.last_request_at) AS last_request_at
   FROM (public.api_key_model_cost akmc
     JOIN public.api_keys ak ON ((ak.id = akmc.api_key_id)))
  GROUP BY akmc.api_key_id, ak.key_alias, ak.tenant_id, ak.application_id;


--
-- Name: goal_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.goal_sessions (
    id integer NOT NULL,
    session_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    state character varying(32) DEFAULT 'active'::character varying NOT NULL,
    original_goal text NOT NULL,
    retry_count integer DEFAULT 0,
    decision_count integer DEFAULT 0,
    auto_continue_count integer DEFAULT 0,
    last_activity_at timestamp without time zone DEFAULT now(),
    completed_at timestamp without time zone,
    audit_result jsonb,
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: goal_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.goal_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: goal_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.goal_sessions_id_seq OWNED BY public.goal_sessions.id;


--
-- Name: handoff_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.handoff_logs (
    id integer NOT NULL,
    session_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    trigger_reason character varying(64) NOT NULL,
    tokens_at_handoff integer NOT NULL,
    context_window integer,
    handoff_prompt text,
    new_session_id character varying(64),
    created_at timestamp without time zone DEFAULT now()
);


--
-- Name: handoff_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.handoff_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: handoff_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.handoff_logs_id_seq OWNED BY public.handoff_logs.id;


--
-- Name: intent_aggregates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.intent_aggregates (
    tenant_id text NOT NULL,
    intent_kind text NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    last_updated timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: internal_service_keys; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.internal_service_keys (
    service_id text NOT NULL,
    secret_hash text NOT NULL,
    description text,
    enabled boolean DEFAULT true NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    rotated_at timestamp with time zone,
    rotation_notes text
);


--
-- Name: key_applications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.key_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_ip inet NOT NULL,
    fingerprint text NOT NULL,
    contact text NOT NULL,
    purpose text,
    status text DEFAULT 'pending'::text NOT NULL,
    issued_key_id bigint,
    admin_notes text,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    expires_at timestamp with time zone DEFAULT (now() + '24:00:00'::interval) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT key_applications_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'expired'::text])))
);


--
-- Name: key_rpm_daily; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.key_rpm_daily (
    api_key_id bigint NOT NULL,
    day_bucket date NOT NULL,
    peak_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    avg_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    request_count bigint DEFAULT 0 NOT NULL
);


--
-- Name: local_models; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.local_models (
    id bigint NOT NULL,
    runtime_id bigint NOT NULL,
    canonical_id bigint,
    raw_name text NOT NULL,
    quantization text,
    size_bytes bigint,
    family text,
    parameters_b numeric(8,2),
    loaded boolean DEFAULT false NOT NULL,
    keep_alive_seconds integer DEFAULT 0 NOT NULL,
    last_used_at timestamp with time zone
);


--
-- Name: local_models_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.local_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: local_models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.local_models_id_seq OWNED BY public.local_models.id;


--
-- Name: local_runtimes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.local_runtimes (
    id bigint NOT NULL,
    host_code text NOT NULL,
    runtime_type text NOT NULL,
    base_url text NOT NULL,
    mode text DEFAULT 'direct'::text NOT NULL,
    status text DEFAULT 'unknown'::text NOT NULL,
    gpu_info_json jsonb,
    vram_total_mb integer,
    vram_used_mb integer,
    ram_total_mb integer,
    last_heartbeat_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT local_runtimes_mode_check CHECK ((mode = ANY (ARRAY['direct'::text, 'agent'::text]))),
    CONSTRAINT local_runtimes_runtime_type_check CHECK ((runtime_type = ANY (ARRAY['ollama'::text, 'vllm'::text, 'llamacpp'::text, 'lmstudio'::text, 'mlx'::text]))),
    CONSTRAINT local_runtimes_status_check CHECK ((status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'degraded'::text, 'offline'::text])))
);


--
-- Name: local_runtimes_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.local_runtimes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: local_runtimes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.local_runtimes_id_seq OWNED BY public.local_runtimes.id;


--
-- Name: maas_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.maas_settings (
    id integer DEFAULT 1 NOT NULL,
    cents_per_credit numeric(10,4) DEFAULT 0.1 NOT NULL,
    base_credits_per_1m bigint DEFAULT 10000 NOT NULL,
    currency_display character varying(8) DEFAULT 'CNY'::character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    alipay_account character varying(128) DEFAULT ''::character varying NOT NULL,
    wechat_mch_id character varying(128) DEFAULT ''::character varying NOT NULL,
    stub_alipay_qr_url text DEFAULT ''::text NOT NULL,
    stub_wechat_qr_url text DEFAULT ''::text NOT NULL,
    base_credits_per_1m_out bigint,
    base_credits_per_1m_cache_in bigint,
    base_credits_per_1m_cache_out bigint,
    global_discount numeric(6,4) DEFAULT 1.0 NOT NULL,
    CONSTRAINT maas_settings_id_check CHECK ((id = 1))
);


--
-- Name: model_aliases; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_aliases (
    id bigint NOT NULL,
    canonical_id bigint NOT NULL,
    raw_name text NOT NULL,
    quantization text,
    surface text,
    status text DEFAULT 'active'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_profiles text[],
    CONSTRAINT model_aliases_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deprecated'::text, 'hidden'::text])))
);


--
-- Name: model_aliases_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.model_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: model_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.model_aliases_id_seq OWNED BY public.model_aliases.id;


--
-- Name: model_cost_per_task_view; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.model_cost_per_task_view AS
 SELECT mcp.canonical_id,
    mcp.raw_model,
    sum(mcp.cost_usd) AS total_cost_usd,
    sum((mcp.tokens_input + mcp.tokens_output)) AS total_tokens,
        CASE
            WHEN (sum((mcp.tokens_input + mcp.tokens_output)) > (0)::numeric) THEN ((sum(mcp.cost_usd) / sum((mcp.tokens_input + mcp.tokens_output))) * (1000000)::numeric)
            ELSE (0)::numeric
        END AS avg_cost_per_1m_usd,
        CASE
            WHEN (sum(mcp.requests_total) > 0) THEN ((sum(mcp.requests_success))::numeric / (sum(mcp.requests_total))::numeric)
            ELSE (0)::numeric
        END AS success_rate,
    ( SELECT avg(rl.latency_ms) AS avg
           FROM public.request_logs rl
          WHERE ((rl.outbound_model = mcp.raw_model) AND (rl.success = true) AND (rl.ts >= (now() - '7 days'::interval)))) AS avg_latency_ms,
    sum(mcp.requests_total) AS total_requests,
    count(DISTINCT mcp.api_key_id) AS unique_api_keys
   FROM public.api_key_model_cost mcp
  WHERE (mcp.bucket >= (now() - '7 days'::interval))
  GROUP BY mcp.canonical_id, mcp.raw_model;


--
-- Name: model_credit_rates; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_credit_rates (
    canonical_id integer NOT NULL,
    credits_per_1m_in bigint,
    credits_per_1m_out bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    credits_per_1m_cache_in bigint,
    credits_per_1m_cache_out bigint,
    manual_in boolean DEFAULT false NOT NULL,
    manual_out boolean DEFAULT false NOT NULL,
    manual_cache_in boolean DEFAULT false NOT NULL,
    manual_cache_out boolean DEFAULT false NOT NULL
);


--
-- Name: model_discovery_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_discovery_runs (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    trigger text DEFAULT 'manual'::text NOT NULL,
    status text DEFAULT 'running'::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    heartbeat_at timestamp with time zone DEFAULT now() NOT NULL,
    lease_expires_at timestamp with time zone NOT NULL,
    requested_by text,
    request_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    summary_json jsonb,
    error text,
    CONSTRAINT chk_model_discovery_runs_status CHECK ((status = ANY (ARRAY['running'::text, 'succeeded'::text, 'failed'::text]))),
    CONSTRAINT chk_model_discovery_runs_trigger CHECK ((trigger = ANY (ARRAY['manual'::text, 'scheduled'::text, 'credential_added'::text])))
);


--
-- Name: model_discovery_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.model_discovery_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: model_discovery_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.model_discovery_runs_id_seq OWNED BY public.model_discovery_runs.id;


--
-- Name: model_families; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_families (
    id text NOT NULL,
    display_name text NOT NULL,
    vendor text,
    status text DEFAULT 'active'::text NOT NULL,
    source text DEFAULT 'db'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT model_families_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deprecated'::text, 'hidden'::text])))
);


--
-- Name: model_fingerprints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_fingerprints (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint NOT NULL,
    fingerprint_hash text NOT NULL,
    sampled_features_json jsonb,
    last_verified_at timestamp with time zone,
    drift_detected boolean DEFAULT false NOT NULL
);


--
-- Name: model_fingerprints_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.model_fingerprints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: model_fingerprints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.model_fingerprints_id_seq OWNED BY public.model_fingerprints.id;


--
-- Name: model_lifecycle_jobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_lifecycle_jobs (
    id bigint NOT NULL,
    runtime_id bigint NOT NULL,
    action text NOT NULL,
    target text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    progress_pct numeric(5,2) DEFAULT 0,
    log text,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT model_lifecycle_jobs_action_check CHECK ((action = ANY (ARRAY['pull'::text, 'rm'::text, 'load'::text, 'unload'::text, 'keepalive'::text]))),
    CONSTRAINT model_lifecycle_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'success'::text, 'failed'::text, 'canceled'::text])))
);


--
-- Name: model_lifecycle_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.model_lifecycle_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: model_lifecycle_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.model_lifecycle_jobs_id_seq OWNED BY public.model_lifecycle_jobs.id;


SET default_table_access_method = columnar;

--
-- Name: model_offer_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_offer_events (
    id bigint,
    ts timestamp with time zone,
    source text,
    action text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    raw_model_name text,
    reason_code text,
    reason_detail text,
    request_id text,
    run_id bigint,
    metadata_json jsonb
);


SET default_table_access_method = heap;

--
-- Name: provider_models; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_models (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    raw_model_name text NOT NULL,
    canonical_id bigint,
    standardized_name text,
    outbound_model_name text,
    available boolean DEFAULT true NOT NULL,
    unavailable_reason text,
    unavailable_at timestamp with time zone,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: model_offers; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.model_offers AS
 SELECT cmb.id,
    cmb.credential_id,
    pm.canonical_id,
    pm.raw_model_name,
    cmb.success_rate,
    cmb.p95_latency_ms,
    cmb.available,
    pm.last_seen_at,
    cmb.routing_tier,
    cmb.weight,
    cmb.unit_price_in_per_1m,
    cmb.unit_price_out_per_1m,
    cmb.currency,
    pm.outbound_model_name,
    cmb.cache_read_price_per_1m,
    cmb.cache_write_price_per_1m,
    pm.standardized_name,
    cmb.unavailable_reason,
    cmb.unavailable_at,
    cmb.billing_mode,
    cmb.pricing_source,
    cmb.pricing_updated_at,
    cmb.manual_priority,
    cmb.active_sessions,
    cmb.consecutive_failures,
    cmb.admin_protected
   FROM (public.credential_model_bindings cmb
     JOIN public.provider_models pm ON ((pm.id = cmb.provider_model_id)));


--
-- Name: model_offers_legacy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_offers_legacy (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    raw_model_name text NOT NULL,
    p95_latency_ms integer,
    success_rate numeric(5,4),
    available boolean DEFAULT true NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    routing_tier smallint DEFAULT 2,
    weight smallint DEFAULT 100,
    unit_price_in_per_1m numeric(12,6),
    unit_price_out_per_1m numeric(12,6),
    currency text DEFAULT 'USD'::text,
    outbound_model_name text,
    cache_read_price_per_1m numeric(12,6),
    cache_write_price_per_1m numeric(12,6),
    standardized_name text,
    unavailable_reason text,
    unavailable_at timestamp with time zone,
    billing_mode text DEFAULT 'per_token'::text,
    pricing_source text,
    pricing_updated_at timestamp with time zone,
    manual_priority smallint DEFAULT 99,
    active_sessions integer DEFAULT 0,
    consecutive_failures integer DEFAULT 0,
    CONSTRAINT model_offers_manual_priority_chk CHECK (((manual_priority >= 1) AND (manual_priority <= 99))),
    CONSTRAINT model_offers_routing_tier_chk CHECK (((routing_tier >= 1) AND (routing_tier <= 9))),
    CONSTRAINT model_offers_weight_chk CHECK (((weight >= 1) AND (weight <= 1000)))
);


--
-- Name: model_offers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.model_offers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: model_offers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.model_offers_id_seq OWNED BY public.model_offers_legacy.id;


SET default_table_access_method = columnar;

--
-- Name: model_probe_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_probe_runs (
    id bigint,
    tenant_id text,
    credential_id bigint,
    raw_model_name text,
    status text,
    http_status integer,
    error_code text,
    error_message text,
    latency_ms integer,
    state_change text,
    state_applied boolean,
    triggered_by text,
    created_at timestamp with time zone
);


SET default_table_access_method = heap;

--
-- Name: model_probe_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_probe_state (
    credential_id bigint NOT NULL,
    raw_model_name text NOT NULL,
    state text DEFAULT 'unknown'::text NOT NULL,
    consecutive_successes integer DEFAULT 0 NOT NULL,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    total_attempts integer DEFAULT 0 NOT NULL,
    last_attempt_at timestamp with time zone,
    next_retry_at timestamp with time zone DEFAULT now() NOT NULL,
    last_status text,
    last_state_change_at timestamp with time zone,
    last_state_change_run bigint,
    last_unavailable_reason text,
    last_err_code text,
    next_retry_at_override timestamp with time zone,
    state_expires_at timestamp with time zone,
    marked_suspicious_at timestamp with time zone,
    probing_started_at timestamp with time zone,
    probing_credential_concurrency integer DEFAULT 0,
    probe_priority text DEFAULT 'watchdog'::text,
    last_verified_at timestamp with time zone,
    verification_interval interval DEFAULT '04:00:00'::interval,
    success_rate_7d numeric(5,2) DEFAULT 0.00,
    consecutive_watchdog_successes integer DEFAULT 0,
    last_real_request_at timestamp with time zone,
    real_request_success_count integer DEFAULT 0,
    real_request_failure_count integer DEFAULT 0,
    CONSTRAINT check_probe_priority CHECK ((probe_priority = ANY (ARRAY['urgent'::text, 'suspicious'::text, 'failing'::text, 'recovering'::text, 'watchdog'::text])))
);


--
-- Name: model_reconcile_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_reconcile_log (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    credential_id bigint,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    added integer DEFAULT 0 NOT NULL,
    removed integer DEFAULT 0 NOT NULL,
    changed integer DEFAULT 0 NOT NULL,
    diff_json jsonb
);


--
-- Name: model_reconcile_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.model_reconcile_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: model_reconcile_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.model_reconcile_log_id_seq OWNED BY public.model_reconcile_log.id;


--
-- Name: model_task_index; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_task_index (
    bucket timestamp with time zone NOT NULL,
    canonical_id integer NOT NULL,
    task_type text NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL,
    success_rate numeric(5,4),
    avg_latency_ms integer,
    p95_latency_ms integer,
    avg_cost_per_1k_usd numeric(10,6),
    primary_credential_id bigint,
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: models_canonical; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.models_canonical (
    id bigint NOT NULL,
    canonical_name text NOT NULL,
    family text,
    parameters_b numeric(8,2),
    modality text DEFAULT 'text'::text NOT NULL,
    context_window integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    tags_locked boolean DEFAULT false NOT NULL,
    tags_updated_at timestamp with time zone,
    display_name text,
    status text DEFAULT 'active'::text NOT NULL,
    source text DEFAULT 'db'::text NOT NULL,
    disabled_reason text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    input_price_cny numeric(10,4) DEFAULT 0,
    output_price_cny numeric(10,4) DEFAULT 0,
    released_at date,
    strengths text[] DEFAULT '{}'::text[] NOT NULL,
    cost_tier text DEFAULT 'unknown'::text NOT NULL,
    multimodal_caps text[] DEFAULT '{}'::text[] NOT NULL,
    version_rank integer,
    CONSTRAINT models_canonical_cost_tier_check CHECK ((cost_tier = ANY (ARRAY['free'::text, 'low'::text, 'medium'::text, 'high'::text, 'premium'::text, 'unknown'::text]))),
    CONSTRAINT models_canonical_modality_check CHECK ((modality = ANY (ARRAY['text'::text, 'vision'::text, 'audio'::text, 'multimodal'::text, 'embedding'::text]))),
    CONSTRAINT models_canonical_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deprecated'::text, 'hidden'::text])))
);


--
-- Name: models_canonical_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.models_canonical_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: models_canonical_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.models_canonical_id_seq OWNED BY public.models_canonical.id;


--
-- Name: ops_model_offers_backup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ops_model_offers_backup (
    backup_id bigint NOT NULL,
    run_tag text NOT NULL,
    backed_at timestamp with time zone DEFAULT now() NOT NULL,
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    raw_model_name text NOT NULL,
    p95_latency_ms integer,
    success_rate numeric(5,4),
    available boolean NOT NULL,
    last_seen_at timestamp with time zone NOT NULL
);


--
-- Name: ops_model_offers_backup_backup_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.ops_model_offers_backup_backup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: ops_model_offers_backup_backup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.ops_model_offers_backup_backup_id_seq OWNED BY public.ops_model_offers_backup.backup_id;


--
-- Name: output_compliance_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.output_compliance_audit (
    id bigint NOT NULL,
    tenant_id character varying(255) NOT NULL,
    request_id character varying(255) NOT NULL,
    session_key character varying(255),
    detected_at timestamp with time zone DEFAULT now(),
    issue_type character varying(50) NOT NULL,
    issue_subtype character varying(50),
    severity integer NOT NULL,
    evidence text,
    location character varying(100),
    score numeric(5,4),
    action_taken character varying(20) NOT NULL,
    redacted boolean DEFAULT false,
    blocked boolean DEFAULT false,
    original_output text,
    redacted_output text,
    model character varying(100),
    client_ip character varying(45),
    CONSTRAINT output_compliance_audit_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);


--
-- Name: output_compliance_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.output_compliance_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: output_compliance_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.output_compliance_audit_id_seq OWNED BY public.output_compliance_audit.id;


--
-- Name: output_compliance_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.output_compliance_policies (
    id integer NOT NULL,
    tenant_id character varying(255) NOT NULL,
    enabled boolean DEFAULT true,
    enforcement_mode character varying(20) DEFAULT 'observe'::character varying,
    check_pii boolean DEFAULT true,
    check_toxicity boolean DEFAULT true,
    check_bias boolean DEFAULT false,
    check_hallucination boolean DEFAULT false,
    pii_threshold numeric(3,2) DEFAULT 0.7,
    toxicity_threshold numeric(3,2) DEFAULT 0.7,
    bias_threshold numeric(3,2) DEFAULT 0.6,
    hallucination_threshold numeric(3,2) DEFAULT 0.7,
    action_on_pii character varying(20) DEFAULT 'redact'::character varying,
    action_on_toxicity character varying(20) DEFAULT 'warn'::character varying,
    action_on_bias character varying(20) DEFAULT 'log'::character varying,
    action_on_hallucination character varying(20) DEFAULT 'log'::character varying,
    auto_redact boolean DEFAULT true,
    redact_email boolean DEFAULT true,
    redact_phone boolean DEFAULT true,
    redact_id_card boolean DEFAULT true,
    redact_credit_card boolean DEFAULT true,
    strict_mode boolean DEFAULT false,
    log_all_outputs boolean DEFAULT false,
    whitelist_patterns text[],
    total_checks integer DEFAULT 0,
    total_issues integer DEFAULT 0,
    total_redactions integer DEFAULT 0,
    last_check_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(255),
    updated_by character varying(255)
);


--
-- Name: output_compliance_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.output_compliance_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: output_compliance_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.output_compliance_policies_id_seq OWNED BY public.output_compliance_policies.id;


--
-- Name: output_compliance_stats_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.output_compliance_stats_today AS
 SELECT output_compliance_audit.tenant_id,
    count(*) AS total_issues,
    count(*) FILTER (WHERE (output_compliance_audit.redacted = true)) AS redacted_count,
    count(*) FILTER (WHERE (output_compliance_audit.blocked = true)) AS blocked_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'pii'::text)) AS pii_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'toxic'::text)) AS toxic_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'bias'::text)) AS bias_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'hallucination'::text)) AS hallucination_count,
    avg(output_compliance_audit.severity) AS avg_severity,
    max(output_compliance_audit.severity) AS max_severity
   FROM public.output_compliance_audit
  WHERE (output_compliance_audit.detected_at >= CURRENT_DATE)
  GROUP BY output_compliance_audit.tenant_id;


--
-- Name: passive_probe_state; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.passive_probe_state (
    credential_id integer NOT NULL,
    raw_model_name text NOT NULL,
    error_kind text NOT NULL,
    consecutive_count integer DEFAULT 0 NOT NULL,
    total_recent_count integer DEFAULT 0 NOT NULL,
    window_total_count integer DEFAULT 0 NOT NULL,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    in_reviewing boolean DEFAULT false NOT NULL,
    reviewing_until timestamp with time zone,
    final_marked_at timestamp with time zone,
    unavailable_reason text,
    last_response_body_preview text
);


--
-- Name: pii_patterns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pii_patterns (
    id integer NOT NULL,
    pattern_name character varying(100) NOT NULL,
    pattern_type character varying(50) NOT NULL,
    regex_pattern text NOT NULL,
    description text,
    enabled boolean DEFAULT true,
    severity integer DEFAULT 7,
    redact_format character varying(100),
    created_at timestamp with time zone DEFAULT now()
);


--
-- Name: pii_patterns_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pii_patterns_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pii_patterns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pii_patterns_id_seq OWNED BY public.pii_patterns.id;


SET default_table_access_method = columnar;

--
-- Name: price_change_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_change_events (
    id bigint,
    old_plan_id bigint,
    new_plan_id bigint,
    delta_json jsonb,
    detected_at timestamp with time zone,
    notify_channel text,
    applied boolean
);


SET default_table_access_method = heap;

--
-- Name: pricing_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pricing_plans (
    id bigint NOT NULL,
    scope text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    tenant_id text,
    model_canonical_id bigint,
    plan_type text NOT NULL,
    currency text DEFAULT 'USD'::text NOT NULL,
    plan_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    effective_from timestamp with time zone DEFAULT now() NOT NULL,
    effective_to timestamp with time zone,
    source text DEFAULT 'manual'::text NOT NULL,
    confidence numeric(4,3) DEFAULT 1.000,
    scraped_url text,
    offer_scope_key text GENERATED ALWAYS AS (((((((((((scope || ':'::text) || COALESCE((provider_id)::text, '-'::text)) || ':'::text) || COALESCE((credential_id)::text, '-'::text)) || ':'::text) || COALESCE(tenant_id, '-'::text)) || ':'::text) || COALESCE((model_canonical_id)::text, '-'::text)) || ':'::text) || plan_type)) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pricing_plans_plan_type_check CHECK ((plan_type = ANY (ARRAY['token'::text, 'token_plan'::text, 'code_plan'::text, 'agent_plan'::text, 'request'::text, 'seat'::text, 'compute_time'::text, 'flat_quota'::text, 'free'::text]))),
    CONSTRAINT pricing_plans_scope_check CHECK ((scope = ANY (ARRAY['provider'::text, 'credential'::text, 'tenant'::text]))),
    CONSTRAINT pricing_plans_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'seed'::text, 'litellm'::text, 'scraped'::text, 'catalog'::text])))
);


--
-- Name: pricing_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pricing_plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pricing_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pricing_plans_id_seq OWNED BY public.pricing_plans.id;


--
-- Name: pricing_refresh_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pricing_refresh_log (
    id bigint NOT NULL,
    run_id text NOT NULL,
    run_ts timestamp with time zone DEFAULT now() NOT NULL,
    trigger text DEFAULT 'cron'::text NOT NULL,
    status text NOT NULL,
    before_summary jsonb NOT NULL,
    after_summary jsonb NOT NULL,
    diff_count integer DEFAULT 0 NOT NULL,
    new_offers integer DEFAULT 0 NOT NULL,
    removed_offers integer DEFAULT 0 NOT NULL,
    changed_offers integer DEFAULT 0 NOT NULL,
    artifacts_path text,
    feishu_sent boolean DEFAULT false NOT NULL,
    error_message text,
    duration_seconds integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pricing_refresh_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.pricing_refresh_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: pricing_refresh_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.pricing_refresh_log_id_seq OWNED BY public.pricing_refresh_log.id;


--
-- Name: prompt_injection_detections; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_injection_detections (
    id bigint NOT NULL,
    tenant_id character varying(255) NOT NULL,
    request_id character varying(255) NOT NULL,
    session_key character varying(255),
    detected_at timestamp with time zone DEFAULT now(),
    risk_level integer NOT NULL,
    rule_id integer,
    rule_name character varying(100),
    category character varying(50),
    matched_pattern text,
    input_sample text,
    blocked boolean DEFAULT false,
    action_taken character varying(20) NOT NULL,
    evidence_text text,
    input_hash character varying(64),
    client_ip character varying(45),
    user_agent text,
    CONSTRAINT prompt_injection_detections_risk_level_check CHECK (((risk_level >= 1) AND (risk_level <= 10)))
);


--
-- Name: prompt_injection_detections_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prompt_injection_detections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prompt_injection_detections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prompt_injection_detections_id_seq OWNED BY public.prompt_injection_detections.id;


--
-- Name: prompt_injection_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prompt_injection_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prompt_injection_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prompt_injection_policies_id_seq OWNED BY public.prompt_injection_policies.id;


--
-- Name: prompt_injection_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_injection_rules (
    id integer NOT NULL,
    rule_name character varying(100) NOT NULL,
    rule_type character varying(50) NOT NULL,
    category character varying(50) NOT NULL,
    pattern text NOT NULL,
    description text,
    severity integer NOT NULL,
    enabled boolean DEFAULT true,
    case_sensitive boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT prompt_injection_rules_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);


--
-- Name: prompt_injection_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.prompt_injection_rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: prompt_injection_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.prompt_injection_rules_id_seq OWNED BY public.prompt_injection_rules.id;


--
-- Name: prompt_injection_stats_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.prompt_injection_stats_today AS
 SELECT prompt_injection_detections.tenant_id,
    count(*) AS total_detections,
    count(*) FILTER (WHERE (prompt_injection_detections.blocked = true)) AS blocked_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level = 10) OR (prompt_injection_detections.risk_level = 9))) AS critical_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level >= 7) AND (prompt_injection_detections.risk_level <= 8))) AS high_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level >= 4) AND (prompt_injection_detections.risk_level <= 6))) AS medium_count,
    count(*) FILTER (WHERE (prompt_injection_detections.risk_level <= 3)) AS low_count,
    avg(prompt_injection_detections.risk_level) AS avg_score,
    max(prompt_injection_detections.risk_level) AS max_score
   FROM public.prompt_injection_detections
  WHERE (prompt_injection_detections.detected_at >= CURRENT_DATE)
  GROUP BY prompt_injection_detections.tenant_id;


--
-- Name: provider_catalog; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_catalog (
    code text NOT NULL,
    tier text NOT NULL,
    display_name text NOT NULL,
    display_name_en text,
    category text DEFAULT 'official'::text NOT NULL,
    kind text DEFAULT 'cloud'::text NOT NULL,
    protocol text NOT NULL,
    base_url_template text NOT NULL,
    docs_url text,
    default_egress_profile text DEFAULT 'direct'::text NOT NULL,
    domestic boolean DEFAULT true NOT NULL,
    discount_rate_default numeric(5,4) DEFAULT 1.0,
    models_manifest_json jsonb DEFAULT '[]'::jsonb,
    discovery_strategy text DEFAULT 'auto'::text NOT NULL,
    models_endpoint_template text,
    seed_pricing_plans_json jsonb DEFAULT '[]'::jsonb,
    price_sources_json jsonb DEFAULT '{}'::jsonb,
    hidden boolean DEFAULT false NOT NULL,
    notes text,
    catalog_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    header_profile_code text,
    capabilities jsonb DEFAULT '{}'::jsonb,
    vendor_name text,
    CONSTRAINT provider_catalog_category_check CHECK ((category = ANY (ARRAY['official'::text, 'official_proxy'::text, 'third_party_relay'::text, 'aggregator'::text, 'self_host'::text]))),
    CONSTRAINT provider_catalog_discovery_strategy_check CHECK ((discovery_strategy = ANY (ARRAY['auto'::text, 'manifest'::text, 'hybrid'::text]))),
    CONSTRAINT provider_catalog_kind_check CHECK ((kind = ANY (ARRAY['cloud'::text, 'local'::text]))),
    CONSTRAINT provider_catalog_protocol_check CHECK ((protocol = ANY (ARRAY['openai-completions'::text, 'openai-responses'::text, 'anthropic-messages'::text, 'gemini-generate'::text, 'ollama-native'::text]))),
    CONSTRAINT provider_catalog_tier_check CHECK ((tier = ANY (ARRAY['tier1'::text, 'tier2'::text, 'local'::text, 'restricted'::text])))
);


SET default_table_access_method = columnar;

--
-- Name: provider_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_events (
    id bigint,
    credential_id bigint,
    event_kind text,
    payload_json jsonb,
    ts timestamp with time zone
);


SET default_table_access_method = heap;

--
-- Name: provider_header_profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_header_profiles (
    id bigint NOT NULL,
    profile_code text NOT NULL,
    display_name text NOT NULL,
    protocol text,
    headers_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    strip_headers_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: provider_header_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.provider_header_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: provider_header_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.provider_header_profiles_id_seq OWNED BY public.provider_header_profiles.id;


--
-- Name: provider_models_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.provider_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: provider_models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.provider_models_id_seq OWNED BY public.provider_models.id;


--
-- Name: provider_quality_rollup; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_quality_rollup (
    provider_id integer NOT NULL,
    bucket_start timestamp with time zone NOT NULL,
    total_requests integer DEFAULT 0 NOT NULL,
    bad_requests integer DEFAULT 0 NOT NULL,
    fixed_requests integer DEFAULT 0 NOT NULL,
    avg_quality_score numeric(3,2),
    top_flag text
);


--
-- Name: provider_scores; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_scores (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    score numeric(6,4) NOT NULL,
    factors_json jsonb,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: provider_scores_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.provider_scores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: provider_scores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.provider_scores_id_seq OWNED BY public.provider_scores.id;


--
-- Name: provider_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_settings (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    setting_key text NOT NULL,
    setting_value jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_by text DEFAULT 'system'::text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: provider_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.provider_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: provider_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.provider_settings_id_seq OWNED BY public.provider_settings.id;


--
-- Name: providers; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.providers (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL,
    catalog_code text,
    is_custom boolean DEFAULT false NOT NULL,
    catalog_version_at_create integer,
    user_overrides_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    kind text DEFAULT 'cloud'::text NOT NULL,
    category text DEFAULT 'official'::text NOT NULL,
    protocol text NOT NULL,
    base_url text NOT NULL,
    egress_profile text DEFAULT 'direct'::text NOT NULL,
    domestic boolean DEFAULT true NOT NULL,
    discount_rate numeric(5,4) DEFAULT 1.0,
    enabled boolean DEFAULT true NOT NULL,
    network_quality_score numeric(4,3) DEFAULT 1.000,
    owner_user text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    manual_disabled boolean DEFAULT false NOT NULL,
    quality_fix_mode text DEFAULT 'off'::text NOT NULL,
    CONSTRAINT providers_category_check CHECK ((category = ANY (ARRAY['official'::text, 'official_proxy'::text, 'third_party_relay'::text, 'aggregator'::text, 'self_host'::text]))),
    CONSTRAINT providers_kind_check CHECK ((kind = ANY (ARRAY['cloud'::text, 'local'::text]))),
    CONSTRAINT providers_quality_fix_mode_check CHECK ((quality_fix_mode = ANY (ARRAY['off'::text, 'detect_only'::text, 'fix'::text])))
);


--
-- Name: providers_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.providers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: providers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.providers_id_seq OWNED BY public.providers.id;


--
-- Name: request_envelope; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_envelope (
    request_id uuid NOT NULL,
    client_model text NOT NULL,
    client_metadata jsonb,
    client_headers_redacted jsonb,
    outbound_model text,
    outbound_protocol text,
    credential_id bigint,
    fingerprint_seed text,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    stream_completed boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);


--
-- Name: request_logs_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs_2026_06 (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);


--
-- Name: request_logs_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs_2026_07 (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);


--
-- Name: request_logs_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs_2026_08 (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);


--
-- Name: request_logs_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs_archive (
    id bigint NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    stream_chunk_errors integer,
    stream_done_sent boolean,
    client_timeout boolean,
    client_endpoint text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    stream_interrupted boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    client_request_id text,
    CONSTRAINT chk_archive_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_archive_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
)
PARTITION BY RANGE (ts);


SET default_table_access_method = columnar;

--
-- Name: request_logs_archive_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs_archive_2026_06 (
    id bigint NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    stream_chunk_errors integer,
    stream_done_sent boolean,
    client_timeout boolean,
    client_endpoint text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    stream_interrupted boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    client_request_id text,
    CONSTRAINT chk_archive_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_archive_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);


--
-- Name: request_logs_archive_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs_archive_2026_07 (
    id bigint NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    stream_chunk_errors integer,
    stream_done_sent boolean,
    client_timeout boolean,
    client_endpoint text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    stream_interrupted boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    client_request_id text,
    CONSTRAINT chk_archive_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_archive_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);


SET default_table_access_method = heap;

--
-- Name: request_logs_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_logs_default (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);


--
-- Name: request_wal; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_wal (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
)
PARTITION BY RANGE (created_at);


--
-- Name: request_wal_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_wal_2026_06 (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
);


--
-- Name: request_wal_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_wal_2026_07 (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
);


--
-- Name: request_wal_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_wal_archive (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
)
PARTITION BY RANGE (created_at);


--
-- Name: request_wal_bodies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_wal_bodies (
    request_id character varying(64) NOT NULL,
    outbound_body text,
    compression_meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: response_format_anomalies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.response_format_anomalies (
    id bigint NOT NULL,
    detected_at timestamp with time zone DEFAULT now() NOT NULL,
    request_id text NOT NULL,
    provider_id integer,
    provider_code text,
    client_model text,
    outbound_model text,
    anomaly_type text NOT NULL,
    severity text DEFAULT 'medium'::text NOT NULL,
    usage_source text,
    expected_tokens integer,
    actual_tokens integer,
    content_size_bytes integer,
    response_structure jsonb,
    response_sample text,
    resolved boolean DEFAULT false NOT NULL,
    resolved_at timestamp with time zone,
    resolution_notes text,
    tenant_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: response_format_anomalies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.response_format_anomalies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: response_format_anomalies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.response_format_anomalies_id_seq OWNED BY public.response_format_anomalies.id;


--
-- Name: route_decisions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.route_decisions (
    id bigint NOT NULL,
    request_id text,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id text,
    api_key_id bigint,
    canonical_id bigint,
    selected_credential_id bigint,
    candidates_json jsonb,
    reason text,
    sticky_hit boolean
);


--
-- Name: route_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.route_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: route_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.route_decisions_id_seq OWNED BY public.route_decisions.id;


--
-- Name: routing_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_audit_log (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now(),
    actor text NOT NULL,
    action text NOT NULL,
    target_type text,
    target_id bigint,
    before_json jsonb,
    after_json jsonb
);


--
-- Name: routing_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.routing_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: routing_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.routing_audit_log_id_seq OWNED BY public.routing_audit_log.id;


--
-- Name: routing_decision_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_decision_log (
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
)
PARTITION BY RANGE (ts);


--
-- Name: routing_decision_log_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_decision_log_2026_06 (
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
);


--
-- Name: routing_decision_log_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_decision_log_2026_07 (
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
);


--
-- Name: routing_decision_log_archive; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_decision_log_archive (
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
)
PARTITION BY RANGE (ts);


--
-- Name: routing_decision_log_default; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_decision_log_default (
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
);


--
-- Name: routing_decision_log_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_decision_log_old (
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
);


--
-- Name: routing_overrides; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_overrides (
    id bigint NOT NULL,
    task_type text NOT NULL,
    profile text DEFAULT ''::text NOT NULL,
    mode text NOT NULL,
    model_chosen text,
    reason text DEFAULT ''::text NOT NULL,
    created_by text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT routing_overrides_mode_check CHECK ((mode = ANY (ARRAY['pin'::text, 'ban'::text])))
);


--
-- Name: routing_overrides_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_overrides_audit (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    action text NOT NULL,
    override_id bigint,
    task_type text,
    profile text,
    mode text,
    model_chosen text,
    reason text,
    expires_at timestamp with time zone,
    old_expires_at timestamp with time zone,
    actor text,
    CONSTRAINT routing_overrides_audit_action_check CHECK ((action = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text])))
);


--
-- Name: routing_overrides_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.routing_overrides_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: routing_overrides_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.routing_overrides_audit_id_seq OWNED BY public.routing_overrides_audit.id;


--
-- Name: routing_overrides_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.routing_overrides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: routing_overrides_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.routing_overrides_id_seq OWNED BY public.routing_overrides.id;


--
-- Name: routing_policy; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_policy (
    id smallint DEFAULT 1 NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    weights_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    sticky_ttl_seconds integer DEFAULT 1800 NOT NULL,
    local_bonus numeric(4,3) DEFAULT 0.000 NOT NULL,
    notes text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    algorithm_version smallint DEFAULT 2,
    retry_per_credential smallint DEFAULT 1,
    tier_fallback_max smallint DEFAULT 4,
    slot_soft_limit_ratio numeric(3,2) DEFAULT 1.00,
    slot_hard_limit_ratio numeric(3,2) DEFAULT 1.50,
    slot_wait_max_ms smallint DEFAULT 200,
    circuit_open_seconds integer DEFAULT 300,
    circuit_failure_threshold smallint DEFAULT 5,
    circuit_max_open_seconds integer DEFAULT 1800,
    featured_models text[] DEFAULT ARRAY['gpt-4o'::text, 'gpt-4o-mini'::text, 'claude-3-5-sonnet-20241022'::text, 'claude-3-7-sonnet-20250219'::text, 'gemini-2.0-flash'::text, 'gemini-1.5-pro'::text, 'deepseek-chat'::text, 'qwen-plus'::text],
    transient_fail_threshold integer DEFAULT 2 NOT NULL,
    stats_window_minutes integer DEFAULT 10,
    stats_update_interval_seconds integer DEFAULT 60,
    scoring_weights_json jsonb DEFAULT '{"price": 10, "session_load": 5, "failure_penalty": 20, "default_price_cny": 5.0, "default_price_usd": 5.0}'::jsonb,
    CONSTRAINT routing_policy_id_check CHECK ((id = 1)),
    CONSTRAINT routing_policy_transient_fail_threshold_check CHECK (((transient_fail_threshold >= 0) AND (transient_fail_threshold <= 10)))
);


--
-- Name: schema_migration_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migration_audit (
    migration_id text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    row_count bigint DEFAULT 0 NOT NULL,
    note text DEFAULT ''::text NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version text NOT NULL,
    description text,
    applied_at timestamp with time zone DEFAULT now()
);


--
-- Name: security_audit_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.security_audit_log (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    event_kind text NOT NULL,
    api_key_id bigint,
    internal_service_id text,
    actor text,
    tenant_id text,
    remote_ip inet,
    detail_json jsonb,
    CONSTRAINT security_audit_log_event_kind_check CHECK ((event_kind = ANY (ARRAY['key_created'::text, 'key_disabled'::text, 'key_throttled'::text, 'key_unthrottled'::text, 'key_revoked'::text, 'key_revealed'::text, 'auth_failed'::text, 'auth_expired'::text, 'admin_login_failed'::text, 'key_reencrypted'::text, 'hmac_sig_failed'::text, 'hmac_nonce_replay'::text, 'hmac_timestamp_bad'::text, 'rate_limited'::text, 'anomaly_spike'::text])))
);


--
-- Name: security_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.security_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: security_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.security_audit_log_id_seq OWNED BY public.security_audit_log.id;


--
-- Name: session_audit_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_audit_records (
    id bigint NOT NULL,
    session_id text NOT NULL,
    tenant_id text NOT NULL,
    request_id text NOT NULL,
    client_ip text,
    client_user_agent text,
    client_model text,
    content_summary text,
    content_title text,
    content_hash text,
    intent_type text,
    intent_score double precision,
    intent_reason text,
    security_score integer,
    danger_score integer,
    trust_score integer,
    sensitive_score integer,
    detect_score integer DEFAULT 0 NOT NULL,
    detect_decision text DEFAULT 'pass'::text NOT NULL,
    threats jsonb DEFAULT '[]'::jsonb NOT NULL,
    sensitive_words jsonb DEFAULT '[]'::jsonb NOT NULL,
    status text DEFAULT 'pass'::text NOT NULL,
    approval_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.session_audit_records FORCE ROW LEVEL SECURITY;


--
-- Name: session_audit_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.session_audit_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: session_audit_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.session_audit_records_id_seq OWNED BY public.session_audit_records.id;


--
-- Name: session_memora_extraction_log; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_memora_extraction_log (
    task_id text NOT NULL,
    extracted_at timestamp with time zone DEFAULT now() NOT NULL,
    written integer DEFAULT 0 NOT NULL,
    skipped_noise integer DEFAULT 0 NOT NULL,
    skipped_duplicate integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'ok'::text NOT NULL,
    detail jsonb
);


--
-- Name: session_summaries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_summaries (
    session_key character varying(255) NOT NULL,
    tenant_id character varying(255) NOT NULL,
    first_request_at timestamp with time zone NOT NULL,
    last_request_at timestamp with time zone NOT NULL,
    duration_seconds integer GENERATED ALWAYS AS ((EXTRACT(epoch FROM (last_request_at - first_request_at)))::integer) STORED,
    request_count integer DEFAULT 0 NOT NULL,
    success_count integer DEFAULT 0 NOT NULL,
    error_count integer DEFAULT 0 NOT NULL,
    total_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    input_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    output_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    total_prompt_tokens bigint DEFAULT 0 NOT NULL,
    total_completion_tokens bigint DEFAULT 0 NOT NULL,
    total_tokens bigint GENERATED ALWAYS AS ((total_prompt_tokens + total_completion_tokens)) STORED,
    avg_latency_ms integer DEFAULT 0 NOT NULL,
    min_latency_ms integer,
    max_latency_ms integer,
    models_used text[] DEFAULT '{}'::text[] NOT NULL,
    primary_model character varying(100),
    model_switch_count integer DEFAULT 0 NOT NULL,
    title character varying(200),
    summary text,
    key_topics text[],
    user_intent character varying(50),
    quality_score integer,
    compliance_status character varying(20) DEFAULT 'compliant'::character varying,
    compliance_issues_count integer DEFAULT 0 NOT NULL,
    prompt_injection_detected boolean DEFAULT false,
    pii_detected boolean DEFAULT false,
    toxic_output_detected boolean DEFAULT false,
    work_types text[],
    providers text[],
    client_models text[],
    last_summarized_at timestamp with time zone,
    summary_version integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT session_summaries_quality_score_check CHECK (((quality_score >= 0) AND (quality_score <= 10)))
);


--
-- Name: session_stats_today; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.session_stats_today AS
 SELECT session_summaries.tenant_id,
    count(*) AS session_count,
    count(*) FILTER (WHERE (session_summaries.last_request_at > (now() - '01:00:00'::interval))) AS active_sessions,
    sum(session_summaries.request_count) AS total_requests,
    sum(session_summaries.total_cost_usd) AS total_cost,
    avg(session_summaries.total_cost_usd) AS avg_cost_per_session,
    avg(session_summaries.total_tokens) AS avg_tokens_per_session,
    avg(session_summaries.avg_latency_ms) AS avg_latency,
    (((count(*) FILTER (WHERE ((session_summaries.compliance_status)::text = 'compliant'::text)))::numeric * 100.0) / (NULLIF(count(*), 0))::numeric) AS compliance_rate,
    (((count(*) FILTER (WHERE (session_summaries.quality_score >= 8)))::numeric * 100.0) / (NULLIF(count(*) FILTER (WHERE (session_summaries.quality_score IS NOT NULL)), 0))::numeric) AS high_quality_rate
   FROM public.session_summaries
  WHERE (session_summaries.first_request_at >= CURRENT_DATE)
  GROUP BY session_summaries.tenant_id;


--
-- Name: session_titles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_titles (
    task_id text NOT NULL,
    scoped_session_id text DEFAULT ''::text NOT NULL,
    title text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    model text,
    api_key_id integer
);


--
-- Name: settings_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings_audit (
    id bigint NOT NULL,
    setting_key character varying(128) NOT NULL,
    tenant_id character varying(64),
    action character varying(16) NOT NULL,
    old_value jsonb,
    new_value jsonb,
    operator_user character varying(64) NOT NULL,
    operator_role character varying(32) NOT NULL,
    confirm_token character varying(64),
    client_ip character varying(45),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.settings_audit FORCE ROW LEVEL SECURITY;


--
-- Name: settings_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.settings_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: settings_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.settings_audit_id_seq OWNED BY public.settings_audit.id;


--
-- Name: settings_kv; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings_kv (
    key character varying(128) NOT NULL,
    value jsonb NOT NULL,
    value_type character varying(32) NOT NULL,
    scope character varying(16) DEFAULT 'platform'::character varying NOT NULL,
    category character varying(32) DEFAULT 'general'::character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by character varying(64),
    prev_value jsonb,
    prev_updated_at timestamp with time zone
);


--
-- Name: sticky_sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sticky_sessions (
    sticky_key text NOT NULL,
    credential_id bigint NOT NULL,
    set_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    canonical_id bigint,
    last_request_id text
);


--
-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscription_plans (
    id integer NOT NULL,
    code character varying(32) NOT NULL,
    tier character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    price_cents integer NOT NULL,
    monthly_credits bigint NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT subscription_plans_tier_check CHECK (((tier)::text = ANY (ARRAY[('basic'::character varying)::text, ('pro'::character varying)::text, ('max'::character varying)::text])))
);


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.subscription_plans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.subscription_plans_id_seq OWNED BY public.subscription_plans.id;


--
-- Name: system_identity_pool; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_identity_pool (
    id integer DEFAULT 1 NOT NULL,
    max_identities integer DEFAULT 10000 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    CONSTRAINT system_identity_pool_id_check CHECK ((id = 1))
);


--
-- Name: tenant_credit_wallets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_credit_wallets (
    tenant_id character varying(64) NOT NULL,
    balance_credits bigint DEFAULT 0 NOT NULL,
    locked_credits bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    granted_balance bigint DEFAULT 0 NOT NULL,
    purchased_balance bigint DEFAULT 0 NOT NULL
);


--
-- Name: tenant_model_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_model_policies (
    id bigint NOT NULL,
    tenant_id character varying(64) NOT NULL,
    canonical_name text NOT NULL,
    reason text DEFAULT ''::text NOT NULL,
    created_by character varying(128) DEFAULT ''::character varying NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenant_model_policies_canonical_name_check CHECK ((canonical_name <> ''::text))
);

ALTER TABLE ONLY public.tenant_model_policies FORCE ROW LEVEL SECURITY;


--
-- Name: tenant_model_policies_active; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.tenant_model_policies_active AS
 SELECT tenant_model_policies.id,
    tenant_model_policies.tenant_id,
    tenant_model_policies.canonical_name,
    tenant_model_policies.reason,
    tenant_model_policies.created_by,
    tenant_model_policies.created_at,
    tenant_model_policies.updated_at
   FROM public.tenant_model_policies
  WHERE (tenant_model_policies.deleted_at IS NULL);


--
-- Name: tenant_model_policies_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_model_policies_audit (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    action text NOT NULL,
    policy_id bigint,
    tenant_id text,
    canonical_name text,
    reason text,
    actor text,
    CONSTRAINT tenant_model_policies_audit_action_check CHECK ((action = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text, 'undelete'::text])))
);

ALTER TABLE ONLY public.tenant_model_policies_audit FORCE ROW LEVEL SECURITY;


--
-- Name: tenant_model_policies_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tenant_model_policies_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenant_model_policies_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tenant_model_policies_audit_id_seq OWNED BY public.tenant_model_policies_audit.id;


--
-- Name: tenant_model_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tenant_model_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenant_model_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tenant_model_policies_id_seq OWNED BY public.tenant_model_policies.id;


--
-- Name: tenant_settings_kv; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_settings_kv (
    tenant_id character varying(64) NOT NULL,
    key character varying(128) NOT NULL,
    value jsonb NOT NULL,
    value_type character varying(32) NOT NULL,
    category character varying(32) DEFAULT 'general'::character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by character varying(64),
    prev_value jsonb,
    prev_updated_at timestamp with time zone
);

ALTER TABLE ONLY public.tenant_settings_kv FORCE ROW LEVEL SECURITY;


--
-- Name: tenant_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_subscriptions (
    id integer NOT NULL,
    tenant_id character varying(64) NOT NULL,
    plan_id integer NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    quota_remaining bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenant_subscriptions_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('active'::character varying)::text, ('expired'::character varying)::text, ('cancelled'::character varying)::text])))
);


--
-- Name: tenant_subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tenant_subscriptions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenant_subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tenant_subscriptions_id_seq OWNED BY public.tenant_subscriptions.id;


--
-- Name: tenant_tool_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenant_tool_policies (
    id bigint NOT NULL,
    tenant_id character varying(64) NOT NULL,
    tool_pattern character varying(128) NOT NULL,
    policy_type character varying(16) NOT NULL,
    reason character varying(256),
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(128),
    CONSTRAINT chk_policy_type CHECK (((policy_type)::text = ANY (ARRAY[('allow'::character varying)::text, ('deny'::character varying)::text])))
);

ALTER TABLE ONLY public.tenant_tool_policies FORCE ROW LEVEL SECURITY;


--
-- Name: tenant_tool_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tenant_tool_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tenant_tool_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tenant_tool_policies_id_seq OWNED BY public.tenant_tool_policies.id;


--
-- Name: tenants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tenants (
    code character varying(64) NOT NULL,
    name character varying(128) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    contact_email character varying(256) DEFAULT ''::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenants_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('trial'::character varying)::text, ('suspended'::character varying)::text, ('expired'::character varying)::text, ('disabled'::character varying)::text])))
);


SET default_table_access_method = columnar;

--
-- Name: test_columnar_new; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.test_columnar_new (
    id integer NOT NULL,
    tenant_id text,
    model text,
    prompt_tokens integer,
    completion_tokens integer,
    created_at timestamp with time zone DEFAULT now()
);


SET default_table_access_method = heap;

--
-- Name: token_audit_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.token_audit_events (
    id bigint NOT NULL,
    request_id text NOT NULL,
    credential_id bigint NOT NULL,
    claimed_tokens integer,
    estimated_tokens integer,
    delta_pct numeric(6,3),
    ts timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: token_audit_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_audit_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_audit_events_id_seq OWNED BY public.token_audit_events.id;


SET default_table_access_method = columnar;

--
-- Name: tool_call_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_call_events (
    id bigint,
    tool_id character varying(128),
    tenant_id character varying(64),
    request_id character varying(64),
    api_key character varying(64),
    status character varying(16),
    latency_ms integer,
    error_code character varying(64),
    called_at timestamp with time zone
);


SET default_table_access_method = heap;

--
-- Name: tool_categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_categories (
    id character varying(64) NOT NULL,
    name character varying(128) NOT NULL,
    description text,
    enabled boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);


--
-- Name: tool_registry; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_registry (
    id integer NOT NULL,
    category character varying(64) NOT NULL,
    tool_name character varying(128) NOT NULL,
    tool_definition jsonb NOT NULL,
    enabled boolean DEFAULT true,
    priority integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    tool_id character varying(128) NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying,
    version integer DEFAULT 1,
    deprecation_date timestamp with time zone,
    min_client_version character varying(32),
    breaking_changes jsonb DEFAULT '[]'::jsonb,
    superseded_by character varying(128)
);


--
-- Name: tool_registry_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tool_registry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tool_registry_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tool_registry_id_seq OWNED BY public.tool_registry.id;


--
-- Name: tool_usage_stats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_usage_stats (
    id bigint NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
)
PARTITION BY RANGE (created_at);


--
-- Name: tool_usage_stats_partitioned_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tool_usage_stats_partitioned_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tool_usage_stats_partitioned_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tool_usage_stats_partitioned_id_seq OWNED BY public.tool_usage_stats.id;


--
-- Name: tool_usage_stats_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_usage_stats_2026_06 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


--
-- Name: tool_usage_stats_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_usage_stats_2026_07 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


--
-- Name: tool_usage_stats_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_usage_stats_2026_08 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);


--
-- Name: tool_usage_stats_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_usage_stats_old (
    id bigint NOT NULL,
    tool_id character varying(128) NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying NOT NULL,
    usage_date date DEFAULT CURRENT_DATE NOT NULL,
    call_count bigint DEFAULT 0 NOT NULL,
    success_count bigint DEFAULT 0 NOT NULL,
    error_count bigint DEFAULT 0 NOT NULL,
    avg_latency_ms integer DEFAULT 0,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.tool_usage_stats_old FORCE ROW LEVEL SECURITY;


--
-- Name: tool_usage_stats_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tool_usage_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tool_usage_stats_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tool_usage_stats_id_seq OWNED BY public.tool_usage_stats_old.id;


--
-- Name: topup_packages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.topup_packages (
    id integer NOT NULL,
    code character varying(32) NOT NULL,
    tier character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    price_cents integer NOT NULL,
    credits_amount bigint NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT topup_packages_tier_check CHECK (((tier)::text = ANY (ARRAY[('small'::character varying)::text, ('medium'::character varying)::text, ('large'::character varying)::text])))
);


--
-- Name: topup_packages_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.topup_packages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: topup_packages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.topup_packages_id_seq OWNED BY public.topup_packages.id;


--
-- Name: toxic_keywords; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.toxic_keywords (
    id integer NOT NULL,
    keyword character varying(100) NOT NULL,
    category character varying(50) NOT NULL,
    severity integer NOT NULL,
    language character varying(10) DEFAULT 'zh'::character varying,
    enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT toxic_keywords_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);


--
-- Name: toxic_keywords_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.toxic_keywords_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: toxic_keywords_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.toxic_keywords_id_seq OWNED BY public.toxic_keywords.id;


--
-- Name: tuning_params; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tuning_params (
    key text NOT NULL,
    value jsonb NOT NULL,
    category text NOT NULL,
    source text DEFAULT 'default'::text NOT NULL,
    confidence numeric(4,3) DEFAULT 1.0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    description text,
    applied_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: tuning_proposals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tuning_proposals (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    category text NOT NULL,
    task_type text,
    proposal jsonb NOT NULL,
    evidence jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    applied_at timestamp with time zone,
    review_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tuning_proposals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'applied'::text, 'expired'::text])))
);


--
-- Name: tuning_proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tuning_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tuning_proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tuning_proposals_id_seq OWNED BY public.tuning_proposals.id;


--
-- Name: tuning_signals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tuning_signals (
    id bigint NOT NULL,
    request_id text NOT NULL,
    session_id text,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    task_type text NOT NULL,
    classifier text NOT NULL,
    confidence numeric(4,3),
    chosen_model text,
    canonical_id integer,
    success_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    latency_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    cost_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    drift_flag boolean DEFAULT false NOT NULL,
    quality_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    latency_ms integer,
    cost_usd numeric(10,6),
    prompt_tokens integer,
    completion_tokens integer,
    signal_payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    strategy text DEFAULT 'pattern_layered'::text NOT NULL,
    CONSTRAINT tuning_signals_strategy_check CHECK ((strategy = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text])))
);


--
-- Name: tuning_signals_5m; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.tuning_signals_5m AS
 SELECT (date_trunc('hour'::text, tuning_signals.ts) + (floor((((EXTRACT(minute FROM tuning_signals.ts))::integer / 5))::double precision) * '00:05:00'::interval)) AS bucket,
    tuning_signals.task_type,
    tuning_signals.classifier,
    count(*) AS total,
    avg(tuning_signals.quality_score) AS avg_quality,
    avg(tuning_signals.success_score) AS avg_success,
    avg(tuning_signals.latency_score) AS avg_latency,
    avg(tuning_signals.cost_score) AS avg_cost,
    ((sum(
        CASE
            WHEN tuning_signals.drift_flag THEN 1
            ELSE 0
        END))::double precision / (NULLIF(count(*), 0))::double precision) AS drift_rate
   FROM public.tuning_signals
  WHERE (tuning_signals.ts >= (now() - '7 days'::interval))
  GROUP BY (date_trunc('hour'::text, tuning_signals.ts) + (floor((((EXTRACT(minute FROM tuning_signals.ts))::integer / 5))::double precision) * '00:05:00'::interval)), tuning_signals.task_type, tuning_signals.classifier
  WITH NO DATA;


--
-- Name: tuning_signals_daily; Type: MATERIALIZED VIEW; Schema: public; Owner: -
--

CREATE MATERIALIZED VIEW public.tuning_signals_daily AS
 SELECT date_trunc('day'::text, tuning_signals.ts) AS bucket,
    tuning_signals.task_type,
    tuning_signals.classifier,
    count(*) AS total,
    avg(tuning_signals.quality_score) AS avg_quality,
    avg(tuning_signals.success_score) AS avg_success,
    avg(tuning_signals.latency_score) AS avg_latency,
    avg(tuning_signals.cost_score) AS avg_cost,
    ((sum(
        CASE
            WHEN tuning_signals.drift_flag THEN 1
            ELSE 0
        END))::double precision / (NULLIF(count(*), 0))::double precision) AS drift_rate
   FROM public.tuning_signals
  WHERE (tuning_signals.ts >= (now() - '90 days'::interval))
  GROUP BY (date_trunc('day'::text, tuning_signals.ts)), tuning_signals.task_type, tuning_signals.classifier
  WITH NO DATA;


--
-- Name: tuning_signals_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.tuning_signals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tuning_signals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.tuning_signals_id_seq OWNED BY public.tuning_signals.id;


--
-- Name: usage_ledger; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_ledger (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
)
PARTITION BY RANGE (ts);


--
-- Name: usage_ledger_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_ledger_2026_06 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


--
-- Name: usage_ledger_2026_07; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_ledger_2026_07 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


--
-- Name: usage_ledger_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_ledger_2026_08 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


--
-- Name: usage_ledger_old; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_ledger_old (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);


--
-- Name: usage_minute; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.usage_minute (
    bucket timestamp with time zone NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    department text,
    employee text,
    "position" text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    requests bigint DEFAULT 0 NOT NULL,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    total_tokens bigint DEFAULT 0 NOT NULL,
    cost_usd numeric(18,8) DEFAULT 0 NOT NULL,
    errors bigint DEFAULT 0 NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id integer NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying NOT NULL,
    username character varying(128) NOT NULL,
    password_hash character varying(256) NOT NULL,
    display_name character varying(128) DEFAULT ''::character varying NOT NULL,
    email character varying(256) DEFAULT ''::character varying NOT NULL,
    role character varying(32) DEFAULT 'tenant_admin'::character varying NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    must_change_password boolean DEFAULT false NOT NULL
);


--
-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


--
-- Name: v_format_anomaly_summary; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_format_anomaly_summary AS
 SELECT date_trunc('hour'::text, response_format_anomalies.detected_at) AS hour,
    response_format_anomalies.provider_code,
    response_format_anomalies.client_model,
    response_format_anomalies.anomaly_type,
    response_format_anomalies.severity,
    count(*) AS anomaly_count,
    count(DISTINCT response_format_anomalies.request_id) AS affected_requests,
    avg(response_format_anomalies.content_size_bytes) AS avg_content_size,
    avg(response_format_anomalies.expected_tokens) AS avg_expected_tokens,
    avg(response_format_anomalies.actual_tokens) AS avg_actual_tokens,
    count(*) FILTER (WHERE response_format_anomalies.resolved) AS resolved_count
   FROM public.response_format_anomalies
  WHERE (response_format_anomalies.detected_at > (now() - '7 days'::interval))
  GROUP BY (date_trunc('hour'::text, response_format_anomalies.detected_at)), response_format_anomalies.provider_code, response_format_anomalies.client_model, response_format_anomalies.anomaly_type, response_format_anomalies.severity;


--
-- Name: v_fp_slot_policy; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_fp_slot_policy AS
 SELECT COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::boolean AS bool
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_enabled'::text)), true) AS enabled,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_max_per_credential'::text)), 100) AS max_per_credential,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::numeric AS "numeric"
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_default_ratio'::text)), 0.25) AS default_ratio,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_client_fingerprint_ttl_days'::text)), 30) AS client_ttl_days,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_max_total_clients'::text)), 10000) AS max_total_clients;


--
-- Name: v_idle_credential_slots; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_idle_credential_slots AS
 SELECT model_probe_state.credential_id,
    model_probe_state.raw_model_name,
    model_probe_state.state,
    model_probe_state.consecutive_failures,
    model_probe_state.last_attempt_at,
    (EXTRACT(epoch FROM (now() - model_probe_state.last_attempt_at)))::integer AS idle_seconds
   FROM public.model_probe_state
  WHERE (model_probe_state.state <> 'broken_confirmed'::text);


--
-- Name: v_model_availability_timeline; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_model_availability_timeline AS
 SELECT mpr.raw_model_name,
    mpr.raw_model_name AS outbound_model_name,
    date_trunc('hour'::text, mpr.created_at) AS hour_bucket,
    count(*) AS total_probes,
    count(*) FILTER (WHERE (mpr.status = 'ok'::text)) AS successful_probes,
    count(*) FILTER (WHERE (mpr.status <> 'ok'::text)) AS failed_probes,
    round((((count(*) FILTER (WHERE (mpr.status = 'ok'::text)))::numeric * 100.0) / (count(*))::numeric), 2) AS success_rate,
    avg(mpr.latency_ms) FILTER (WHERE (mpr.status = 'ok'::text)) AS avg_latency_ms,
    count(DISTINCT mpr.credential_id) AS probed_credentials,
    count(DISTINCT mpr.credential_id) FILTER (WHERE (mpr.status = 'ok'::text)) AS successful_credentials,
    count(DISTINCT mpr.credential_id) FILTER (WHERE (mpr.status <> 'ok'::text)) AS failed_credentials
   FROM public.model_probe_runs mpr
  WHERE (mpr.created_at >= (now() - '24:00:00'::interval))
  GROUP BY mpr.raw_model_name, (date_trunc('hour'::text, mpr.created_at))
  ORDER BY mpr.raw_model_name, (date_trunc('hour'::text, mpr.created_at)) DESC;


--
-- Name: v_model_health_dashboard; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_model_health_dashboard AS
 WITH model_stats AS (
         SELECT mps.raw_model_name,
            mps.raw_model_name AS outbound_model_name,
            'openai-completions'::text AS protocol,
            p.display_name AS provider_name,
            count(*) AS total_credentials,
            count(*) FILTER (WHERE (mps.state = ANY (ARRAY['healthy_confirmed'::text, 'healthy'::text]))) AS healthy_count,
            count(*) FILTER (WHERE (mps.state = 'suspicious'::text)) AS suspicious_count,
            count(*) FILTER (WHERE (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text]))) AS failing_count,
            count(*) FILTER (WHERE (mps.state = 'probing'::text)) AS probing_count,
            sum(
                CASE
                    WHEN (mps.consecutive_failures >= 3) THEN 1
                    ELSE 0
                END) AS urgent_count,
            count(*) FILTER (WHERE (mps.state = 'suspicious'::text)) AS suspicious_priority_count,
            count(*) FILTER (WHERE (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text]))) AS failing_priority_count,
            count(*) FILTER (WHERE (mps.state = 'healthy_confirmed'::text)) AS watchdog_count,
            avg(
                CASE
                    WHEN (mps.total_attempts > 0) THEN (((mps.consecutive_successes)::double precision / (mps.total_attempts)::double precision) * (100)::double precision)
                    ELSE NULL::double precision
                END) AS avg_success_rate_7d,
            avg((EXTRACT(epoch FROM (mps.next_retry_at - now())) / (3600)::numeric)) AS avg_verification_hours,
            avg(mps.consecutive_successes) AS avg_consecutive_successes,
            0 AS total_real_success_24h,
            0 AS total_real_failure_24h,
            max(mps.last_attempt_at) AS last_verified_at,
            max(mps.last_attempt_at) AS last_real_request_at,
            min(mps.next_retry_at) AS next_probe_at,
            sum(
                CASE
                    WHEN ((mps.state = ANY (ARRAY['failing'::text, 'broken_confirmed'::text])) AND (mps.consecutive_failures >= 3)) THEN 1
                    ELSE 0
                END) AS critical_nodes,
            count(*) FILTER (WHERE ((mps.next_retry_at <= (now() + '00:05:00'::interval)) AND (mps.state <> 'probing'::text))) AS pending_probes_5min
           FROM ((public.model_probe_state mps
             JOIN public.credentials c ON ((c.id = mps.credential_id)))
             JOIN public.providers p ON ((p.id = c.provider_id)))
          WHERE ((COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false))
          GROUP BY mps.raw_model_name, p.display_name
        )
 SELECT 0 AS provider_model_id,
    model_stats.raw_model_name,
    model_stats.outbound_model_name,
    model_stats.protocol,
    model_stats.provider_name,
    model_stats.total_credentials,
    model_stats.healthy_count,
    model_stats.suspicious_count,
    model_stats.failing_count,
    model_stats.probing_count,
    round((((model_stats.healthy_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) AS healthy_percentage,
    round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) AS failing_percentage,
    model_stats.urgent_count,
    model_stats.suspicious_priority_count,
    model_stats.failing_priority_count,
    model_stats.watchdog_count,
    round((model_stats.avg_success_rate_7d)::numeric, 2) AS avg_success_rate_7d,
    round(model_stats.avg_verification_hours, 1) AS avg_verification_hours,
    round(model_stats.avg_consecutive_successes, 1) AS avg_consecutive_successes,
    model_stats.total_real_success_24h,
    model_stats.total_real_failure_24h,
        CASE
            WHEN ((model_stats.total_real_success_24h + model_stats.total_real_failure_24h) > 0) THEN round((((model_stats.total_real_success_24h)::numeric * 100.0) / ((model_stats.total_real_success_24h + model_stats.total_real_failure_24h))::numeric), 2)
            ELSE NULL::numeric
        END AS real_success_rate_24h,
    model_stats.last_verified_at,
    model_stats.last_real_request_at,
    model_stats.next_probe_at,
    model_stats.critical_nodes,
    model_stats.pending_probes_5min,
        CASE
            WHEN (model_stats.critical_nodes > 0) THEN 'critical'::text
            WHEN (round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) > (20)::numeric) THEN 'warning'::text
            WHEN (round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) > (10)::numeric) THEN 'degraded'::text
            WHEN (round((((model_stats.healthy_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) >= (90)::numeric) THEN 'healthy'::text
            ELSE 'unknown'::text
        END AS overall_health
   FROM model_stats
  ORDER BY
        CASE
            WHEN (model_stats.critical_nodes > 0) THEN 1
            WHEN (model_stats.urgent_count > 0) THEN 2
            WHEN (round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) > (20)::numeric) THEN 3
            ELSE 4
        END, model_stats.total_credentials DESC, model_stats.raw_model_name;


--
-- Name: v_model_priority_details; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_model_priority_details AS
 SELECT mps.raw_model_name,
    mps.raw_model_name AS outbound_model_name,
        CASE
            WHEN (mps.consecutive_failures >= 3) THEN 'urgent'::text
            WHEN (mps.state = 'suspicious'::text) THEN 'suspicious'::text
            WHEN (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text])) THEN 'failing'::text
            ELSE 'watchdog'::text
        END AS probe_priority,
    mps.state,
    c.id AS credential_id,
    c.label AS credential_label,
    p.display_name AS provider_name,
    mps.last_attempt_at AS last_verified_at,
    mps.next_retry_at,
    mps.last_attempt_at AS marked_suspicious_at,
    NULL::timestamp without time zone AS probing_started_at,
    mps.consecutive_successes,
    mps.consecutive_failures,
    0 AS consecutive_watchdog_successes,
        CASE
            WHEN (mps.total_attempts > 0) THEN (((mps.consecutive_successes)::double precision / (mps.total_attempts)::double precision) * (100)::double precision)
            ELSE NULL::double precision
        END AS success_rate_7d,
    (mps.next_retry_at - now()) AS verification_interval,
    0 AS real_success_24h,
    0 AS real_failure_24h,
    mps.last_attempt_at AS last_real_request_at,
    NULL::text AS last_unavailable_reason,
    mps.last_status AS last_err_code,
        CASE
            WHEN (mps.next_retry_at <= now()) THEN 'ready'::text
            WHEN (mps.next_retry_at <= (now() + '00:01:00'::interval)) THEN '<1min'::text
            WHEN (mps.next_retry_at <= (now() + '00:05:00'::interval)) THEN '<5min'::text
            WHEN (mps.next_retry_at <= (now() + '01:00:00'::interval)) THEN '<1h'::text
            ELSE '>1h'::text
        END AS retry_in,
    (EXTRACT(epoch FROM (now() - mps.last_attempt_at)) / (60)::numeric) AS state_duration_minutes
   FROM ((public.model_probe_state mps
     JOIN public.credentials c ON ((c.id = mps.credential_id)))
     JOIN public.providers p ON ((p.id = c.provider_id)))
  WHERE ((COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false))
  ORDER BY mps.raw_model_name,
        CASE
            WHEN (mps.consecutive_failures >= 3) THEN 1
            WHEN (mps.state = 'suspicious'::text) THEN 2
            WHEN (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text])) THEN 3
            ELSE 4
        END, c.id;


--
-- Name: v_probe_queue_snapshot; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_probe_queue_snapshot AS
 SELECT sub.probe_priority,
    sub.state,
    count(*) AS queue_size,
    count(*) FILTER (WHERE (sub.next_retry_at <= now())) AS ready_now,
    count(*) FILTER (WHERE (sub.next_retry_at <= (now() + '00:01:00'::interval))) AS ready_1min,
    count(*) FILTER (WHERE (sub.next_retry_at <= (now() + '00:05:00'::interval))) AS ready_5min,
    min(sub.next_retry_at) AS earliest_retry_at,
    max(sub.next_retry_at) AS latest_retry_at,
    avg(EXTRACT(epoch FROM (now() - sub.last_attempt_at))) AS avg_wait_seconds,
    max(EXTRACT(epoch FROM (now() - sub.last_attempt_at))) AS max_wait_seconds
   FROM ( SELECT
                CASE
                    WHEN (mps.consecutive_failures >= 3) THEN 'urgent'::text
                    WHEN (mps.state = 'suspicious'::text) THEN 'suspicious'::text
                    WHEN (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text])) THEN 'failing'::text
                    WHEN (mps.state = 'healthy_confirmed'::text) THEN 'watchdog'::text
                    ELSE 'unknown'::text
                END AS probe_priority,
            mps.state,
            mps.next_retry_at,
            mps.last_attempt_at
           FROM (public.model_probe_state mps
             JOIN public.credentials c ON ((c.id = mps.credential_id)))
          WHERE ((mps.state = ANY (ARRAY['suspicious'::text, 'failing'::text, 'recovering'::text])) AND (COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false))) sub
  GROUP BY sub.probe_priority, sub.state
  ORDER BY
        CASE
            WHEN (sub.probe_priority = 'urgent'::text) THEN 1
            WHEN (sub.probe_priority = 'suspicious'::text) THEN 2
            WHEN (sub.probe_priority = 'failing'::text) THEN 3
            WHEN (sub.probe_priority = 'watchdog'::text) THEN 4
            ELSE 5
        END, sub.state;


--
-- Name: v_probe_system_health; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_probe_system_health AS
 SELECT ( SELECT count(*) AS count
           FROM public.model_probe_state) AS total_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = ANY (ARRAY['healthy_confirmed'::text, 'healthy'::text]))) AS healthy_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = ANY (ARRAY['failing'::text, 'broken_confirmed'::text]))) AS failing_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'suspicious'::text)) AS suspicious_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'probing'::text)) AS probing_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.consecutive_failures >= 3)) AS urgent_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'suspicious'::text)) AS suspicious_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = ANY (ARRAY['failing'::text, 'recovering'::text]))) AS failing_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'healthy_confirmed'::text)) AS watchdog_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE ((model_probe_state.next_retry_at <= now()) AND (model_probe_state.state <> 'probing'::text))) AS ready_probes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'probing'::text)) AS current_probing,
    ( SELECT count(DISTINCT model_probe_state.credential_id) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'probing'::text)) AS credentials_being_probed,
    ( SELECT round((avg(
                CASE
                    WHEN (model_probe_state.total_attempts > 0) THEN (((model_probe_state.consecutive_successes)::double precision / (model_probe_state.total_attempts)::double precision) * (100)::double precision)
                    ELSE NULL::double precision
                END))::numeric, 2) AS round
           FROM public.model_probe_state) AS avg_success_rate_7d,
    ( SELECT max(model_probe_state.last_attempt_at) AS max
           FROM public.model_probe_state) AS last_probe_at,
    ( SELECT max(model_probe_state.last_attempt_at) AS max
           FROM public.model_probe_state) AS last_real_request_at,
    0 AS total_real_success_24h,
    0 AS total_real_failure_24h,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE ((model_probe_state.state = ANY (ARRAY['failing'::text, 'broken_confirmed'::text])) AND (model_probe_state.consecutive_failures >= 5))) AS critical_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE ((model_probe_state.next_retry_at <= (now() + '00:05:00'::interval)) AND (model_probe_state.state <> 'probing'::text))) AS pending_probes_5min,
    now() AS snapshot_at;


--
-- Name: v_routable_credential_models; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_routable_credential_models AS
 SELECT cmb.id AS binding_id,
    cmb.credential_id,
    cmb.provider_model_id,
    c.tenant_id,
    p.id AS provider_id,
    c.label AS credential_label,
    pm.raw_model_name,
    pm.canonical_id,
        CASE
            WHEN (NOT p.enabled) THEN 'provider_disabled'::text
            WHEN COALESCE(p.manual_disabled, false) THEN 'provider_manual_disabled'::text
            WHEN (c.status <> 'active'::text) THEN ('credential_status_'::text || c.status)
            WHEN (c.lifecycle_status <> 'active'::text) THEN ('lifecycle_'::text || c.lifecycle_status)
            WHEN COALESCE(c.manual_disabled, false) THEN 'credential_manual_disabled'::text
            WHEN (c.availability_state = 'cooling'::text) THEN 'availability_cooling'::text
            WHEN (c.availability_state = 'rate_limited'::text) THEN 'availability_rate_limited'::text
            WHEN (c.availability_state = 'auth_failed'::text) THEN 'availability_auth_failed'::text
            WHEN (c.availability_state = 'unreachable'::text) THEN 'availability_unreachable'::text
            WHEN (c.availability_state = 'suspended'::text) THEN 'availability_suspended'::text
            WHEN (c.quota_state = ANY (ARRAY['permanently_exhausted'::text, 'balance_exhausted'::text])) THEN ('quota_'::text || c.quota_state)
            WHEN ((c.health_status = 'unreachable'::text) AND (c.health_checked_at > (now() - '01:00:00'::interval))) THEN 'recent_probe_unreachable'::text
            WHEN (NOT pm.available) THEN 'model_unavailable'::text
            WHEN (cmb.unavailable_reason = 'manual'::text) THEN 'model_manual_disabled'::text
            WHEN (NOT cmb.available) THEN 'binding_unavailable'::text
            ELSE NULL::text
        END AS unavailable_reason,
    (p.enabled AND (COALESCE(p.manual_disabled, false) = false) AND (c.status = 'active'::text) AND (c.lifecycle_status = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false) AND (c.availability_state = 'ready'::text) AND (c.quota_state <> ALL (ARRAY['permanently_exhausted'::text, 'balance_exhausted'::text])) AND (pm.available = true) AND (cmb.available = true) AND (cmb.unavailable_reason IS DISTINCT FROM 'manual'::text) AND (COALESCE(c.health_status, 'unknown'::text) = ANY (ARRAY['healthy'::text, 'unknown'::text]))) AS is_routable,
    (((((cmb.manual_priority * 100))::numeric + (COALESCE(cmb.success_rate, 0.5) * (50)::numeric)) - (COALESCE(cmb.unit_price_in_per_1m, (0)::numeric) * 0.001)) - ((COALESCE(cmb.p95_latency_ms, 1000))::numeric * 0.01)) AS routing_score
   FROM (((public.credential_model_bindings cmb
     JOIN public.credentials c ON ((c.id = cmb.credential_id)))
     JOIN public.providers p ON ((p.id = c.provider_id)))
     JOIN public.provider_models pm ON ((pm.id = cmb.provider_model_id)));


--
-- Name: v_suspicious_probe_targets; Type: VIEW; Schema: public; Owner: -
--

CREATE VIEW public.v_suspicious_probe_targets AS
 SELECT mps.credential_id,
    pm.raw_model_name,
    COALESCE(pm.outbound_model_name, ''::text) AS outbound_model_name,
    COALESCE(p.base_url, ''::text) AS base_url,
    COALESCE(p.protocol, 'openai-completions'::text) AS protocol,
    mps.marked_suspicious_at,
    mps.next_retry_at,
    mps.consecutive_failures,
    mps.consecutive_successes,
    public.model_probe_credential_concurrency(mps.credential_id) AS credential_probe_count
   FROM (((public.model_probe_state mps
     JOIN public.credentials c ON ((c.id = mps.credential_id)))
     JOIN public.providers p ON ((p.id = c.provider_id)))
     JOIN public.provider_models pm ON (((pm.raw_model_name = mps.raw_model_name) AND (EXISTS ( SELECT 1
           FROM public.credential_model_bindings cmb
          WHERE ((cmb.credential_id = mps.credential_id) AND (cmb.provider_model_id = pm.id)))))))
  WHERE ((mps.state = 'suspicious'::text) AND (mps.next_retry_at <= now()) AND (COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false) AND (COALESCE(p.enabled, false) = true) AND (COALESCE(p.manual_disabled, false) = false) AND (public.model_probe_credential_concurrency(mps.credential_id) < 2))
  ORDER BY (public.model_probe_credential_concurrency(mps.credential_id)), mps.marked_suspicious_at, mps.next_retry_at
 LIMIT 100;


--
-- Name: work_type_config; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_type_config (
    key text NOT NULL,
    label text NOT NULL,
    category text NOT NULL,
    l1_task_type text NOT NULL,
    default_profile text DEFAULT 'smart'::text NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    prompt_keywords text[] DEFAULT '{}'::text[] NOT NULL,
    acc_task_type text,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    synced_from_acc_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    system_prompt text,
    CONSTRAINT work_type_config_default_profile_check CHECK ((default_profile = ANY (ARRAY['smart'::text, 'speed_first'::text, 'cost_first'::text])))
);


--
-- Name: work_type_model_route; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.work_type_model_route (
    id integer NOT NULL,
    work_type_key text NOT NULL,
    canonical_name text NOT NULL,
    weight numeric(5,2) DEFAULT 1.0 NOT NULL,
    min_score numeric(8,4) DEFAULT 0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    tier text DEFAULT 'secondary'::text NOT NULL,
    task_quality_score numeric(5,2) DEFAULT 0 NOT NULL,
    CONSTRAINT work_type_model_route_task_quality_score_check CHECK (((task_quality_score >= (0)::numeric) AND (task_quality_score <= (100)::numeric))),
    CONSTRAINT work_type_model_route_tier_check CHECK ((tier = ANY (ARRAY['primary'::text, 'secondary'::text, 'fallback'::text])))
);


--
-- Name: work_type_model_route_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.work_type_model_route_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: work_type_model_route_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.work_type_model_route_id_seq OWNED BY public.work_type_model_route.id;


--
-- Name: credential_model_index_archive_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_index_archive ATTACH PARTITION public.credential_model_index_archive_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: credit_ledger_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: credit_ledger_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: credit_ledger_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


--
-- Name: request_logs_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: request_logs_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: request_logs_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


--
-- Name: request_logs_archive_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_logs_archive ATTACH PARTITION public.request_logs_archive_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: request_logs_archive_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_logs_archive ATTACH PARTITION public.request_logs_archive_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: request_logs_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_default DEFAULT;


--
-- Name: request_wal_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: request_wal_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: routing_decision_log_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: routing_decision_log_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: routing_decision_log_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_default DEFAULT;


--
-- Name: tool_usage_stats_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: tool_usage_stats_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: tool_usage_stats_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


--
-- Name: usage_ledger_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
-- Name: usage_ledger_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--
-- Name: usage_ledger_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


--
-- Name: agents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents ALTER COLUMN id SET DEFAULT nextval('public.agents_id_seq'::regclass);


--
-- Name: analysis_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_events ALTER COLUMN id SET DEFAULT nextval('public.analysis_events_id_seq'::regclass);


--
-- Name: api_keys id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys ALTER COLUMN id SET DEFAULT nextval('public.api_keys_id_seq'::regclass);


--
-- Name: applications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications ALTER COLUMN id SET DEFAULT nextval('public.applications_id_seq'::regclass);


--
-- Name: armor_judgments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.armor_judgments ALTER COLUMN id SET DEFAULT nextval('public.armor_judgments_id_seq'::regclass);


--
-- Name: auto_tune_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.auto_tune_audit ALTER COLUMN id SET DEFAULT nextval('public.auto_tune_audit_id_seq'::regclass);


--
-- Name: background_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.background_tasks ALTER COLUMN id SET DEFAULT nextval('public.background_tasks_id_seq'::regclass);


--
-- Name: billing_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_orders ALTER COLUMN id SET DEFAULT nextval('public.billing_orders_id_seq'::regclass);


--
-- Name: credential_capabilities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_capabilities ALTER COLUMN id SET DEFAULT nextval('public.credential_capabilities_id_seq'::regclass);


--
-- Name: credential_health_checks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_health_checks ALTER COLUMN id SET DEFAULT nextval('public.credential_health_checks_id_seq'::regclass);


--
-- Name: credential_model_bindings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_bindings ALTER COLUMN id SET DEFAULT nextval('public.credential_model_bindings_id_seq'::regclass);


--
-- Name: credential_quota_usage id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_quota_usage ALTER COLUMN id SET DEFAULT nextval('public.credential_quota_usage_id_seq'::regclass);


--
-- Name: credential_quotas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_quotas ALTER COLUMN id SET DEFAULT nextval('public.credential_quotas_id_seq'::regclass);


--
-- Name: credentials id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials ALTER COLUMN id SET DEFAULT nextval('public.credentials_id_seq'::regclass);


--
-- Name: credit_ledger id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger ALTER COLUMN id SET DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass);


--
-- Name: credit_ledger_old id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger_old ALTER COLUMN id SET DEFAULT nextval('public.credit_ledger_id_seq'::regclass);


--
-- Name: goal_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goal_sessions ALTER COLUMN id SET DEFAULT nextval('public.goal_sessions_id_seq'::regclass);


--
-- Name: handoff_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.handoff_logs ALTER COLUMN id SET DEFAULT nextval('public.handoff_logs_id_seq'::regclass);


--
-- Name: local_models id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local_models ALTER COLUMN id SET DEFAULT nextval('public.local_models_id_seq'::regclass);


--
-- Name: local_runtimes id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local_runtimes ALTER COLUMN id SET DEFAULT nextval('public.local_runtimes_id_seq'::regclass);


--
-- Name: model_aliases id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_aliases ALTER COLUMN id SET DEFAULT nextval('public.model_aliases_id_seq'::regclass);


--
-- Name: model_discovery_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_discovery_runs ALTER COLUMN id SET DEFAULT nextval('public.model_discovery_runs_id_seq'::regclass);


--
-- Name: model_fingerprints id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_fingerprints ALTER COLUMN id SET DEFAULT nextval('public.model_fingerprints_id_seq'::regclass);


--
-- Name: model_lifecycle_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_lifecycle_jobs ALTER COLUMN id SET DEFAULT nextval('public.model_lifecycle_jobs_id_seq'::regclass);


--
-- Name: model_offers_legacy id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_offers_legacy ALTER COLUMN id SET DEFAULT nextval('public.model_offers_id_seq'::regclass);


--
-- Name: model_reconcile_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_reconcile_log ALTER COLUMN id SET DEFAULT nextval('public.model_reconcile_log_id_seq'::regclass);


--
-- Name: models_canonical id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.models_canonical ALTER COLUMN id SET DEFAULT nextval('public.models_canonical_id_seq'::regclass);


--
-- Name: ops_model_offers_backup backup_id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ops_model_offers_backup ALTER COLUMN backup_id SET DEFAULT nextval('public.ops_model_offers_backup_backup_id_seq'::regclass);


--
-- Name: output_compliance_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.output_compliance_audit ALTER COLUMN id SET DEFAULT nextval('public.output_compliance_audit_id_seq'::regclass);


--
-- Name: output_compliance_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.output_compliance_policies ALTER COLUMN id SET DEFAULT nextval('public.output_compliance_policies_id_seq'::regclass);


--
-- Name: pii_patterns id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pii_patterns ALTER COLUMN id SET DEFAULT nextval('public.pii_patterns_id_seq'::regclass);


--
-- Name: pricing_plans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pricing_plans ALTER COLUMN id SET DEFAULT nextval('public.pricing_plans_id_seq'::regclass);


--
-- Name: pricing_refresh_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pricing_refresh_log ALTER COLUMN id SET DEFAULT nextval('public.pricing_refresh_log_id_seq'::regclass);


--
-- Name: prompt_injection_detections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_detections ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_detections_id_seq'::regclass);


--
-- Name: prompt_injection_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_policies ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_policies_id_seq'::regclass);


--
-- Name: prompt_injection_rules id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_rules ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_rules_id_seq'::regclass);


--
-- Name: provider_header_profiles id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_header_profiles ALTER COLUMN id SET DEFAULT nextval('public.provider_header_profiles_id_seq'::regclass);


--
-- Name: provider_models id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_models ALTER COLUMN id SET DEFAULT nextval('public.provider_models_id_seq'::regclass);


--
-- Name: provider_scores id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_scores ALTER COLUMN id SET DEFAULT nextval('public.provider_scores_id_seq'::regclass);


--
-- Name: provider_settings id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_settings ALTER COLUMN id SET DEFAULT nextval('public.provider_settings_id_seq'::regclass);


--
-- Name: providers id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers ALTER COLUMN id SET DEFAULT nextval('public.providers_id_seq'::regclass);


--
-- Name: response_format_anomalies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.response_format_anomalies ALTER COLUMN id SET DEFAULT nextval('public.response_format_anomalies_id_seq'::regclass);


--
-- Name: route_decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route_decisions ALTER COLUMN id SET DEFAULT nextval('public.route_decisions_id_seq'::regclass);


--
-- Name: routing_audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_audit_log ALTER COLUMN id SET DEFAULT nextval('public.routing_audit_log_id_seq'::regclass);


--
-- Name: routing_overrides id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_overrides ALTER COLUMN id SET DEFAULT nextval('public.routing_overrides_id_seq'::regclass);


--
-- Name: routing_overrides_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_overrides_audit ALTER COLUMN id SET DEFAULT nextval('public.routing_overrides_audit_id_seq'::regclass);


--
-- Name: security_audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.security_audit_log ALTER COLUMN id SET DEFAULT nextval('public.security_audit_log_id_seq'::regclass);


--
-- Name: session_audit_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_audit_records ALTER COLUMN id SET DEFAULT nextval('public.session_audit_records_id_seq'::regclass);


--
-- Name: settings_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.settings_audit ALTER COLUMN id SET DEFAULT nextval('public.settings_audit_id_seq'::regclass);


--
-- Name: subscription_plans id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans ALTER COLUMN id SET DEFAULT nextval('public.subscription_plans_id_seq'::regclass);


--
-- Name: tenant_model_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_model_policies ALTER COLUMN id SET DEFAULT nextval('public.tenant_model_policies_id_seq'::regclass);


--
-- Name: tenant_model_policies_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_model_policies_audit ALTER COLUMN id SET DEFAULT nextval('public.tenant_model_policies_audit_id_seq'::regclass);


--
-- Name: tenant_subscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_subscriptions ALTER COLUMN id SET DEFAULT nextval('public.tenant_subscriptions_id_seq'::regclass);


--
-- Name: tenant_tool_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_tool_policies ALTER COLUMN id SET DEFAULT nextval('public.tenant_tool_policies_id_seq'::regclass);


--
-- Name: token_audit_events id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.token_audit_events ALTER COLUMN id SET DEFAULT nextval('public.token_audit_events_id_seq'::regclass);


--
-- Name: tool_registry id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_registry ALTER COLUMN id SET DEFAULT nextval('public.tool_registry_id_seq'::regclass);


--
-- Name: tool_usage_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats ALTER COLUMN id SET DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass);


--
-- Name: tool_usage_stats_old id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_old ALTER COLUMN id SET DEFAULT nextval('public.tool_usage_stats_id_seq'::regclass);


--
-- Name: topup_packages id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topup_packages ALTER COLUMN id SET DEFAULT nextval('public.topup_packages_id_seq'::regclass);


--
-- Name: toxic_keywords id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.toxic_keywords ALTER COLUMN id SET DEFAULT nextval('public.toxic_keywords_id_seq'::regclass);


--
-- Name: tuning_proposals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tuning_proposals ALTER COLUMN id SET DEFAULT nextval('public.tuning_proposals_id_seq'::regclass);


--
-- Name: tuning_signals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tuning_signals ALTER COLUMN id SET DEFAULT nextval('public.tuning_signals_id_seq'::regclass);


--
-- Name: users id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


--
-- Name: work_type_model_route id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_type_model_route ALTER COLUMN id SET DEFAULT nextval('public.work_type_model_route_id_seq'::regclass);


--
-- Name: agents agents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_pkey PRIMARY KEY (id);


--
-- Name: analysis_events analysis_events_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_events
    ADD CONSTRAINT analysis_events_event_id_key UNIQUE (event_id);


--
-- Name: analysis_events analysis_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.analysis_events
    ADD CONSTRAINT analysis_events_pkey PRIMARY KEY (id);


--
-- Name: api_keys api_keys_key_hash_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_key_hash_key UNIQUE (key_hash);


--
-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


--
-- Name: applications applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_pkey PRIMARY KEY (id);


--
-- Name: applications applications_tenant_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_tenant_id_code_key UNIQUE (tenant_id, code);


--
-- Name: approval_queue approval_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.approval_queue
    ADD CONSTRAINT approval_queue_pkey PRIMARY KEY (id);


--
-- Name: armor_judgments armor_judgments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.armor_judgments
    ADD CONSTRAINT armor_judgments_pkey PRIMARY KEY (id);


--
-- Name: background_tasks background_tasks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.background_tasks
    ADD CONSTRAINT background_tasks_pkey PRIMARY KEY (id);


--
-- Name: billing_orders billing_orders_order_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_orders
    ADD CONSTRAINT billing_orders_order_no_key UNIQUE (order_no);


--
-- Name: credential_model_bindings cmb_unique_credential_model; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_bindings
    ADD CONSTRAINT cmb_unique_credential_model UNIQUE (credential_id, provider_model_id);


--
-- Name: credential_capabilities credential_capabilities_credential_id_capability_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_capabilities
    ADD CONSTRAINT credential_capabilities_credential_id_capability_key UNIQUE (credential_id, capability);


--
-- Name: credential_model_call_history credential_model_call_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_call_history
    ADD CONSTRAINT credential_model_call_history_pkey PRIMARY KEY (credential_id, raw_model, window_start);


--
-- Name: credential_model_index credential_model_index_bucket_cred_model_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_index
    ADD CONSTRAINT credential_model_index_bucket_cred_model_key UNIQUE (bucket, credential_id, raw_model);


--
-- Name: credential_quota_usage credential_quota_usage_quota_id_window_started_at_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_quota_usage
    ADD CONSTRAINT credential_quota_usage_quota_id_window_started_at_key UNIQUE (quota_id, window_started_at);


--
-- Name: credential_quotas credential_quotas_credential_id_quota_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_quotas
    ADD CONSTRAINT credential_quotas_credential_id_quota_name_key UNIQUE (credential_id, quota_name);


--
-- Name: credentials credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (id);


--
-- Name: credentials credentials_unique_provider_label; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_unique_provider_label UNIQUE (provider_id, tenant_id, label);


--
-- Name: credit_ledger credit_ledger_partitioned_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger
    ADD CONSTRAINT credit_ledger_partitioned_pkey PRIMARY KEY (id, created_at);


--
-- Name: credit_ledger_2026_06 credit_ledger_2026_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger_2026_06
    ADD CONSTRAINT credit_ledger_2026_06_pkey PRIMARY KEY (id, created_at);


--
-- Name: credit_ledger_2026_07 credit_ledger_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger_2026_07
    ADD CONSTRAINT credit_ledger_2026_07_pkey PRIMARY KEY (id, created_at);


--
-- Name: credit_ledger_2026_08 credit_ledger_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger_2026_08
    ADD CONSTRAINT credit_ledger_2026_08_pkey PRIMARY KEY (id, created_at);


--
-- Name: goal_sessions goal_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goal_sessions
    ADD CONSTRAINT goal_sessions_pkey PRIMARY KEY (id);


--
-- Name: goal_sessions goal_sessions_session_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goal_sessions
    ADD CONSTRAINT goal_sessions_session_id_key UNIQUE (session_id);


--
-- Name: handoff_logs handoff_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.handoff_logs
    ADD CONSTRAINT handoff_logs_pkey PRIMARY KEY (id);


--
-- Name: intent_aggregates intent_aggregates_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.intent_aggregates
    ADD CONSTRAINT intent_aggregates_pkey PRIMARY KEY (tenant_id, intent_kind);


--
-- Name: local_models local_models_runtime_id_raw_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local_models
    ADD CONSTRAINT local_models_runtime_id_raw_name_key UNIQUE (runtime_id, raw_name);


--
-- Name: local_runtimes local_runtimes_host_code_runtime_type_base_url_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local_runtimes
    ADD CONSTRAINT local_runtimes_host_code_runtime_type_base_url_key UNIQUE (host_code, runtime_type, base_url);


--
-- Name: maas_settings maas_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.maas_settings
    ADD CONSTRAINT maas_settings_pkey PRIMARY KEY (id);


--
-- Name: model_fingerprints model_fingerprints_credential_id_canonical_id_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_fingerprints
    ADD CONSTRAINT model_fingerprints_credential_id_canonical_id_key UNIQUE (credential_id, canonical_id);


--
-- Name: model_offers_legacy model_offers_credential_id_raw_model_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_offers_legacy
    ADD CONSTRAINT model_offers_credential_id_raw_model_name_key UNIQUE (credential_id, raw_model_name);


--
-- Name: model_probe_state model_probe_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_probe_state
    ADD CONSTRAINT model_probe_state_pkey PRIMARY KEY (credential_id, raw_model_name);


--
-- Name: model_task_index model_task_index_bucket_canonical_task_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_task_index
    ADD CONSTRAINT model_task_index_bucket_canonical_task_key UNIQUE (bucket, canonical_id, task_type);


--
-- Name: models_canonical models_canonical_canonical_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.models_canonical
    ADD CONSTRAINT models_canonical_canonical_name_key UNIQUE (canonical_name);


--
-- Name: output_compliance_audit output_compliance_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.output_compliance_audit
    ADD CONSTRAINT output_compliance_audit_pkey PRIMARY KEY (id);


--
-- Name: output_compliance_policies output_compliance_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT output_compliance_policies_pkey PRIMARY KEY (id);


--
-- Name: passive_probe_state passive_probe_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.passive_probe_state
    ADD CONSTRAINT passive_probe_state_pkey PRIMARY KEY (credential_id, raw_model_name, error_kind);


--
-- Name: pii_patterns pii_patterns_pattern_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pii_patterns
    ADD CONSTRAINT pii_patterns_pattern_name_key UNIQUE (pattern_name);


--
-- Name: pii_patterns pii_patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pii_patterns
    ADD CONSTRAINT pii_patterns_pkey PRIMARY KEY (id);


--
-- Name: agent_relationships pk_agent_relationships; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT pk_agent_relationships PRIMARY KEY (src_agent_id, dst_agent_id, rel);


--
-- Name: asset_relationships pk_asset_relationships; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT pk_asset_relationships PRIMARY KEY (src_kind, src_ref_id, dst_kind, dst_ref_id, rel);


--
-- Name: assets pk_assets; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT pk_assets PRIMARY KEY (kind, ref_id);


--
-- Name: prompt_injection_detections prompt_injection_detections_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_detections
    ADD CONSTRAINT prompt_injection_detections_pkey PRIMARY KEY (id);


--
-- Name: prompt_injection_policies prompt_injection_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT prompt_injection_policies_pkey PRIMARY KEY (id);


--
-- Name: prompt_injection_rules prompt_injection_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_rules
    ADD CONSTRAINT prompt_injection_rules_pkey PRIMARY KEY (id);


--
-- Name: prompt_injection_rules prompt_injection_rules_rule_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_rules
    ADD CONSTRAINT prompt_injection_rules_rule_name_key UNIQUE (rule_name);


--
-- Name: provider_header_profiles provider_header_profiles_profile_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_header_profiles
    ADD CONSTRAINT provider_header_profiles_profile_code_key UNIQUE (profile_code);


--
-- Name: provider_models provider_models_unique_provider_model; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_models
    ADD CONSTRAINT provider_models_unique_provider_model UNIQUE (provider_id, raw_model_name);


--
-- Name: provider_quality_rollup provider_quality_rollup_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_quality_rollup
    ADD CONSTRAINT provider_quality_rollup_pkey PRIMARY KEY (provider_id, bucket_start);


--
-- Name: provider_settings provider_settings_unique_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_settings
    ADD CONSTRAINT provider_settings_unique_key UNIQUE (provider_id, setting_key);


--
-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


--
-- Name: providers providers_tenant_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_tenant_id_code_key UNIQUE (tenant_id, code);


--
-- Name: request_wal request_wal_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_wal
    ADD CONSTRAINT request_wal_pkey PRIMARY KEY (request_id, created_at);


--
-- Name: request_wal_2026_06 request_wal_2026_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_wal_2026_06
    ADD CONSTRAINT request_wal_2026_06_pkey PRIMARY KEY (request_id, created_at);


--
-- Name: request_wal_2026_07 request_wal_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_wal_2026_07
    ADD CONSTRAINT request_wal_2026_07_pkey PRIMARY KEY (request_id, created_at);


--
-- Name: response_format_anomalies response_format_anomalies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.response_format_anomalies
    ADD CONSTRAINT response_format_anomalies_pkey PRIMARY KEY (id);


--
-- Name: session_audit_records session_audit_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_audit_records
    ADD CONSTRAINT session_audit_records_pkey PRIMARY KEY (id);


--
-- Name: session_summaries session_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT session_summaries_pkey PRIMARY KEY (session_key);


--
-- Name: subscription_plans subscription_plans_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_code_key UNIQUE (code);


--
-- Name: system_identity_pool system_identity_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.system_identity_pool
    ADD CONSTRAINT system_identity_pool_pkey PRIMARY KEY (id);


--
-- Name: tenant_model_policies tenant_model_policies_tenant_id_canonical_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_model_policies
    ADD CONSTRAINT tenant_model_policies_tenant_id_canonical_name_key UNIQUE (tenant_id, canonical_name);


--
-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (code);


--
-- Name: tool_registry tool_registry_tool_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_registry
    ADD CONSTRAINT tool_registry_tool_name_key UNIQUE (tool_name);


--
-- Name: tool_usage_stats tool_usage_stats_partitioned_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats
    ADD CONSTRAINT tool_usage_stats_partitioned_pkey PRIMARY KEY (id, created_at);


--
-- Name: tool_usage_stats_2026_06 tool_usage_stats_2026_06_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_2026_06
    ADD CONSTRAINT tool_usage_stats_2026_06_pkey PRIMARY KEY (id, created_at);


--
-- Name: tool_usage_stats tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats
    ADD CONSTRAINT tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


--
-- Name: tool_usage_stats_2026_06 tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_2026_06
    ADD CONSTRAINT tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


--
-- Name: tool_usage_stats_2026_07 tool_usage_stats_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_2026_07
    ADD CONSTRAINT tool_usage_stats_2026_07_pkey PRIMARY KEY (id, created_at);


--
-- Name: tool_usage_stats_2026_07 tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_2026_07
    ADD CONSTRAINT tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


--
-- Name: tool_usage_stats_2026_08 tool_usage_stats_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_2026_08
    ADD CONSTRAINT tool_usage_stats_2026_08_pkey PRIMARY KEY (id, created_at);


--
-- Name: tool_usage_stats_2026_08 tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_2026_08
    ADD CONSTRAINT tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);


--
-- Name: topup_packages topup_packages_code_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.topup_packages
    ADD CONSTRAINT topup_packages_code_key UNIQUE (code);


--
-- Name: toxic_keywords toxic_keywords_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.toxic_keywords
    ADD CONSTRAINT toxic_keywords_pkey PRIMARY KEY (id);


--
-- Name: tenant_tool_policies uk_tenant_tool_policy; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_tool_policies
    ADD CONSTRAINT uk_tenant_tool_policy UNIQUE (tenant_id, tool_pattern);


--
-- Name: tool_usage_stats_old uk_tool_usage_stats; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats_old
    ADD CONSTRAINT uk_tool_usage_stats UNIQUE (tool_id, tenant_id, usage_date);


--
-- Name: output_compliance_policies unique_output_compliance_tenant; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT unique_output_compliance_tenant UNIQUE (tenant_id);


--
-- Name: prompt_injection_policies unique_tenant_policy; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT unique_tenant_policy UNIQUE (tenant_id);


--
-- Name: usage_ledger usage_ledger_partitioned_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger
    ADD CONSTRAINT usage_ledger_partitioned_request_id_ts_key UNIQUE (request_id, ts);


--
-- Name: usage_ledger_2026_06 usage_ledger_2026_06_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger_2026_06
    ADD CONSTRAINT usage_ledger_2026_06_request_id_ts_key UNIQUE (request_id, ts);


--
-- Name: usage_ledger_2026_07 usage_ledger_2026_07_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger_2026_07
    ADD CONSTRAINT usage_ledger_2026_07_request_id_ts_key UNIQUE (request_id, ts);


--
-- Name: usage_ledger_2026_08 usage_ledger_2026_08_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger_2026_08
    ADD CONSTRAINT usage_ledger_2026_08_request_id_ts_key UNIQUE (request_id, ts);


--
-- Name: usage_ledger_old usage_ledger_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger_old
    ADD CONSTRAINT usage_ledger_pkey PRIMARY KEY (request_id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


--
-- Name: work_type_config work_type_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_type_config
    ADD CONSTRAINT work_type_config_pkey PRIMARY KEY (key);


--
-- Name: work_type_model_route work_type_model_route_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_type_model_route
    ADD CONSTRAINT work_type_model_route_pkey PRIMARY KEY (id);


--
-- Name: work_type_model_route work_type_model_route_work_type_key_canonical_name_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_type_model_route
    ADD CONSTRAINT work_type_model_route_work_type_key_canonical_name_key UNIQUE (work_type_key, canonical_name);


--
-- Name: idx_cmi_archive_cred_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_cred_model ON ONLY public.credential_model_index_archive USING btree (credential_id, raw_model, bucket DESC);


--
-- Name: credential_model_index_archiv_credential_id_raw_model_bucke_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credential_model_index_archiv_credential_id_raw_model_bucke_idx ON public.credential_model_index_archive_2026_06 USING btree (credential_id, raw_model, bucket DESC);


--
-- Name: idx_cmi_archive_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_bucket ON ONLY public.credential_model_index_archive USING btree (bucket DESC);


--
-- Name: credential_model_index_archive_2026_06_bucket_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credential_model_index_archive_2026_06_bucket_idx ON public.credential_model_index_archive_2026_06 USING btree (bucket DESC);


--
-- Name: idx_cmi_archive_canonical; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_canonical ON ONLY public.credential_model_index_archive USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);


--
-- Name: credential_model_index_archive_2026_06_canonical_id_bucket_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credential_model_index_archive_2026_06_canonical_id_bucket_idx ON public.credential_model_index_archive_2026_06 USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);


--
-- Name: idx_credit_ledger_part_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_ledger_part_created ON ONLY public.credit_ledger USING btree (created_at);


--
-- Name: credit_ledger_2026_06_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_06_created_at_idx ON public.credit_ledger_2026_06 USING btree (created_at);


--
-- Name: idx_credit_ledger_part_ref; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_ledger_part_ref ON ONLY public.credit_ledger USING btree (ref_type, ref_id);


--
-- Name: credit_ledger_2026_06_ref_type_ref_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_06_ref_type_ref_id_idx ON public.credit_ledger_2026_06 USING btree (ref_type, ref_id);


--
-- Name: idx_credit_ledger_part_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_ledger_part_tenant ON ONLY public.credit_ledger USING btree (tenant_id, created_at);


--
-- Name: credit_ledger_2026_06_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_06_tenant_id_created_at_idx ON public.credit_ledger_2026_06 USING btree (tenant_id, created_at);


--
-- Name: credit_ledger_2026_07_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_07_created_at_idx ON public.credit_ledger_2026_07 USING btree (created_at);


--
-- Name: credit_ledger_2026_07_ref_type_ref_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_07_ref_type_ref_id_idx ON public.credit_ledger_2026_07 USING btree (ref_type, ref_id);


--
-- Name: credit_ledger_2026_07_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_07_tenant_id_created_at_idx ON public.credit_ledger_2026_07 USING btree (tenant_id, created_at);


--
-- Name: credit_ledger_2026_08_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_08_created_at_idx ON public.credit_ledger_2026_08 USING btree (created_at);


--
-- Name: credit_ledger_2026_08_ref_type_ref_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_08_ref_type_ref_id_idx ON public.credit_ledger_2026_08 USING btree (ref_type, ref_id);


--
-- Name: credit_ledger_2026_08_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credit_ledger_2026_08_tenant_id_created_at_idx ON public.credit_ledger_2026_08 USING btree (tenant_id, created_at);


--
-- Name: idx_agent_rel_dst; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_rel_dst ON public.agent_relationships USING btree (dst_agent_id);


--
-- Name: idx_agent_rel_src; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_rel_src ON public.agent_relationships USING btree (src_agent_id);


--
-- Name: idx_agents_capabilities; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_capabilities ON public.agents USING gin (capabilities jsonb_path_ops);


--
-- Name: idx_agents_heartbeat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_heartbeat ON public.agents USING btree (last_heartbeat) WHERE (last_heartbeat IS NOT NULL);


--
-- Name: idx_agents_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_kind ON public.agents USING btree (tenant_id, kind);


--
-- Name: idx_agents_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_tenant ON public.agents USING btree (tenant_id);


--
-- Name: idx_analysis_events_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_analysis_events_session ON public.analysis_events USING btree (session_id, occurred_at DESC) WHERE (session_id IS NOT NULL);


--
-- Name: idx_analysis_events_tenant_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_analysis_events_tenant_type ON public.analysis_events USING btree (tenant_id, type, occurred_at DESC);


--
-- Name: idx_analysis_events_unprocessed; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_analysis_events_unprocessed ON public.analysis_events USING btree (occurred_at) WHERE (processed_at IS NULL);


--
-- Name: idx_applications_tenant_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_applications_tenant_code ON public.applications USING btree (tenant_id, code) WHERE (enabled = true);


--
-- Name: idx_approval_queue_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_expires ON public.approval_queue USING btree (expires_at) WHERE (status = 'pending'::text);


--
-- Name: idx_approval_queue_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_session ON public.approval_queue USING btree (session_id, created_at DESC);


--
-- Name: idx_approval_queue_tenant_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_tenant_pending ON public.approval_queue USING btree (tenant_id, created_at DESC) WHERE (status = 'pending'::text);


--
-- Name: idx_armor_judgments_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_armor_judgments_request ON public.armor_judgments USING btree (request_id);


--
-- Name: idx_armor_judgments_stats; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_armor_judgments_stats ON public.armor_judgments USING btree (check_type, decision);


--
-- Name: idx_armor_judgments_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_armor_judgments_tenant_time ON public.armor_judgments USING btree (tenant_id, created_at DESC);


--
-- Name: idx_asset_rel_dst; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_asset_rel_dst ON public.asset_relationships USING btree (dst_kind, dst_ref_id);


--
-- Name: idx_asset_rel_src; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_asset_rel_src ON public.asset_relationships USING btree (src_kind, src_ref_id);


--
-- Name: idx_assets_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assets_tags ON public.assets USING gin (tags jsonb_path_ops);


--
-- Name: idx_assets_tenant_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assets_tenant_kind ON public.assets USING btree (tenant_id, kind);


--
-- Name: idx_billing_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_orders_status ON public.billing_orders USING btree (status, created_at DESC);


--
-- Name: idx_billing_orders_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_orders_tenant ON public.billing_orders USING btree (tenant_id, created_at DESC);


--
-- Name: idx_call_history_cred_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_call_history_cred_time ON public.credential_model_call_history USING btree (credential_id, window_start DESC);


--
-- Name: idx_call_history_errors; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_call_history_errors ON public.credential_model_call_history USING btree (credential_id, raw_model, window_start DESC) WHERE ((error_rate_limit_count > 0) OR (error_concurrent_count > 0));


--
-- Name: idx_call_history_model_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_call_history_model_time ON public.credential_model_call_history USING btree (raw_model, window_start DESC);


--
-- Name: idx_cmb_unavailable_recover_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmb_unavailable_recover_at ON public.credential_model_bindings USING btree (unavailable_recover_at) WHERE (available = false);


--
-- Name: idx_credentials_auto_limit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credentials_auto_limit ON public.credentials USING btree (concurrency_limit_auto) WHERE (concurrency_limit_auto IS NOT NULL);


--
-- Name: idx_credit_ledger_tenant_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credit_ledger_tenant_ts ON public.credit_ledger_old USING btree (tenant_id, created_at DESC);


--
-- Name: idx_detections_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_detections_request ON public.prompt_injection_detections USING btree (request_id);


--
-- Name: idx_detections_risk; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_detections_risk ON public.prompt_injection_detections USING btree (tenant_id, risk_level) WHERE (blocked = true);


--
-- Name: idx_detections_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_detections_session ON public.prompt_injection_detections USING btree (session_key);


--
-- Name: idx_detections_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_detections_tenant_time ON public.prompt_injection_detections USING btree (tenant_id, detected_at DESC);


--
-- Name: idx_goal_sessions_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_sessions_session ON public.goal_sessions USING btree (session_id);


--
-- Name: idx_goal_sessions_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_sessions_state ON public.goal_sessions USING btree (state, last_activity_at);


--
-- Name: idx_goal_sessions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_sessions_tenant ON public.goal_sessions USING btree (tenant_id, state);


--
-- Name: idx_handoff_logs_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_handoff_logs_session ON public.handoff_logs USING btree (session_id, created_at DESC);


--
-- Name: idx_handoff_logs_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_handoff_logs_tenant ON public.handoff_logs USING btree (tenant_id, created_at DESC);


--
-- Name: idx_intent_aggregates_tenant_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_intent_aggregates_tenant_updated ON public.intent_aggregates USING btree (tenant_id, last_updated DESC);


--
-- Name: idx_model_probe_state_retry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_model_probe_state_retry ON public.model_probe_state USING btree (state, next_retry_at) WHERE (state = 'recovering'::text);


--
-- Name: idx_models_canonical_released; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_models_canonical_released ON public.models_canonical USING btree (released_at DESC NULLS LAST);


--
-- Name: idx_models_canonical_strengths; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_models_canonical_strengths ON public.models_canonical USING gin (strengths);


--
-- Name: idx_models_canonical_version_rank; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_models_canonical_version_rank ON public.models_canonical USING btree (version_rank);


--
-- Name: idx_mps_due; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_due ON public.model_probe_state USING btree (next_retry_at) WHERE (state = ANY (ARRAY['unknown'::text, 'recovering'::text]));


--
-- Name: idx_mps_priority_next_retry; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_priority_next_retry ON public.model_probe_state USING btree (probe_priority, next_retry_at) WHERE (state = ANY (ARRAY['suspicious'::text, 'failing'::text, 'recovering'::text]));


--
-- Name: idx_mps_probing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_probing ON public.model_probe_state USING btree (probing_started_at) WHERE (state = 'probing'::text);


--
-- Name: idx_mps_success_rate; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_success_rate ON public.model_probe_state USING btree (success_rate_7d);


--
-- Name: idx_mps_suspicious_expired; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_suspicious_expired ON public.model_probe_state USING btree (state_expires_at) WHERE ((state = ANY (ARRAY['available'::text, 'unavailable'::text])) AND (state_expires_at IS NOT NULL));


--
-- Name: idx_mps_suspicious_pending; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_mps_suspicious_pending ON public.model_probe_state USING btree (marked_suspicious_at, next_retry_at) WHERE (state = 'suspicious'::text);


--
-- Name: idx_output_audit_issue; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_output_audit_issue ON public.output_compliance_audit USING btree (tenant_id, issue_type, severity DESC);


--
-- Name: idx_output_audit_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_output_audit_request ON public.output_compliance_audit USING btree (request_id);


--
-- Name: idx_output_audit_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_output_audit_session ON public.output_compliance_audit USING btree (session_key);


--
-- Name: idx_output_audit_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_output_audit_tenant_time ON public.output_compliance_audit USING btree (tenant_id, detected_at DESC);


--
-- Name: idx_passive_probe_reviewing; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_passive_probe_reviewing ON public.passive_probe_state USING btree (in_reviewing, reviewing_until) WHERE (in_reviewing = true);


--
-- Name: idx_provider_quality_rollup_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_quality_rollup_bucket ON public.provider_quality_rollup USING btree (bucket_start DESC);


--
-- Name: idx_provider_settings_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_settings_key ON public.provider_settings USING btree (setting_key) WHERE (enabled = true);


--
-- Name: idx_provider_settings_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_settings_provider ON public.provider_settings USING btree (provider_id) WHERE (enabled = true);


--
-- Name: idx_request_logs_client_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model ON ONLY public.request_logs USING btree (client_model);


--
-- Name: idx_request_logs_client_model_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model_hash ON ONLY public.request_logs USING hash (client_model);


--
-- Name: idx_request_logs_client_model_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model_lower ON ONLY public.request_logs USING btree (lower(client_model));


--
-- Name: idx_request_logs_client_model_prefix; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model_prefix ON ONLY public.request_logs USING btree (client_model text_pattern_ops);


--
-- Name: idx_request_logs_client_model_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model_trgm ON ONLY public.request_logs USING gin (client_model public.gin_trgm_ops);


--
-- Name: idx_request_logs_client_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_request_id ON ONLY public.request_logs USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


--
-- Name: idx_request_logs_credits_charged; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_credits_charged ON ONLY public.request_logs USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


--
-- Name: idx_request_logs_gw_session_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_gw_session_ts ON ONLY public.request_logs USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


--
-- Name: idx_request_logs_gw_task_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_gw_task_ts ON ONLY public.request_logs USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: idx_request_logs_outbound_msg_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_outbound_msg_count ON ONLY public.request_logs USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
-- Name: idx_request_logs_parent_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_parent_ts ON ONLY public.request_logs USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


--
-- Name: idx_request_logs_provider_quality; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_provider_quality ON ONLY public.request_logs USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


--
-- Name: idx_request_logs_provider_tool_calls; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_provider_tool_calls ON ONLY public.request_logs USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


--
-- Name: idx_request_logs_quality_flags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_quality_flags ON ONLY public.request_logs USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
-- Name: idx_request_logs_request_id_ts_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_request_logs_request_id_ts_unique ON ONLY public.request_logs USING btree (request_id, ts);


--
-- Name: idx_request_logs_session_outbound; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_session_outbound ON ONLY public.request_logs USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


--
-- Name: idx_request_logs_status_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_status_ts ON ONLY public.request_logs USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
-- Name: idx_request_logs_tenant_task_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_tenant_task_ts ON ONLY public.request_logs USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: idx_request_logs_tool_calls; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_tool_calls ON ONLY public.request_logs USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


--
-- Name: idx_request_logs_upstream_finish_reason; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_upstream_finish_reason ON ONLY public.request_logs USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


--
-- Name: idx_request_logs_work_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_work_type ON ONLY public.request_logs USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


--
-- Name: idx_response_format_anomalies_detected_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_response_format_anomalies_detected_at ON public.response_format_anomalies USING btree (detected_at DESC);


--
-- Name: idx_response_format_anomalies_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_response_format_anomalies_provider ON public.response_format_anomalies USING btree (provider_code, client_model) WHERE (provider_code IS NOT NULL);


--
-- Name: idx_response_format_anomalies_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_response_format_anomalies_request_id ON public.response_format_anomalies USING btree (request_id);


--
-- Name: idx_response_format_anomalies_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_response_format_anomalies_type ON public.response_format_anomalies USING btree (anomaly_type, detected_at DESC);


--
-- Name: idx_response_format_anomalies_unresolved; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_response_format_anomalies_unresolved ON public.response_format_anomalies USING btree (detected_at DESC) WHERE (NOT resolved);


--
-- Name: idx_routing_decision_log_part_credential; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_credential ON ONLY public.routing_decision_log USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--
-- Name: idx_routing_decision_log_part_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_model ON ONLY public.routing_decision_log USING btree (model, ts DESC);


--
-- Name: idx_routing_decision_log_part_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_request_id ON ONLY public.routing_decision_log USING btree (request_id);


--
-- Name: idx_routing_decision_log_part_success; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_success ON ONLY public.routing_decision_log USING btree (success, ts DESC);


--
-- Name: idx_routing_decision_log_part_tenant_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_tenant_ts ON ONLY public.routing_decision_log USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--
-- Name: idx_routing_decision_log_part_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_ts ON ONLY public.routing_decision_log USING btree (ts DESC);


--
-- Name: idx_routing_overrides_audit_actor_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_audit_actor_ts ON public.routing_overrides_audit USING btree (actor, ts DESC) WHERE (actor IS NOT NULL);


--
-- Name: idx_routing_overrides_audit_override_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_audit_override_ts ON public.routing_overrides_audit USING btree (override_id, ts DESC) WHERE (override_id IS NOT NULL);


--
-- Name: idx_routing_overrides_audit_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_audit_ts ON public.routing_overrides_audit USING btree (ts DESC);


--
-- Name: idx_routing_overrides_expires; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_expires ON public.routing_overrides USING btree (expires_at) WHERE (expires_at IS NOT NULL);


--
-- Name: idx_routing_overrides_task_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_task_profile ON public.routing_overrides USING btree (task_type, profile);


--
-- Name: idx_routing_overrides_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_routing_overrides_unique ON public.routing_overrides USING btree (task_type, profile, COALESCE(model_chosen, ''::text), mode);


--
-- Name: idx_session_audit_records_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_audit_records_session ON public.session_audit_records USING btree (session_id, created_at DESC);


--
-- Name: idx_session_audit_records_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_audit_records_status ON public.session_audit_records USING btree (status, created_at DESC) WHERE (status = 'need_approval'::text);


--
-- Name: idx_session_audit_records_tenant_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_audit_records_tenant_created ON public.session_audit_records USING btree (tenant_id, created_at DESC);


--
-- Name: idx_session_memora_extraction_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_memora_extraction_at ON public.session_memora_extraction_log USING btree (extracted_at DESC);


--
-- Name: idx_session_summaries_compliance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_compliance ON public.session_summaries USING btree (tenant_id, compliance_status) WHERE ((compliance_status)::text <> 'compliant'::text);


--
-- Name: idx_session_summaries_cost; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_cost ON public.session_summaries USING btree (tenant_id, total_cost_usd DESC);


--
-- Name: idx_session_summaries_intent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_intent ON public.session_summaries USING btree (tenant_id, user_intent) WHERE (user_intent IS NOT NULL);


--
-- Name: idx_session_summaries_models; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_models ON public.session_summaries USING gin (models_used);


--
-- Name: idx_session_summaries_quality; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_quality ON public.session_summaries USING btree (quality_score DESC) WHERE (quality_score IS NOT NULL);


--
-- Name: idx_session_summaries_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_tenant_time ON public.session_summaries USING btree (tenant_id, last_request_at DESC);


--
-- Name: idx_session_summaries_topics; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_topics ON public.session_summaries USING gin (key_topics);


--
-- Name: idx_session_titles_generated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_titles_generated_at ON public.session_titles USING btree (generated_at DESC);


--
-- Name: idx_settings_audit_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_audit_created ON public.settings_audit USING btree (created_at);


--
-- Name: idx_settings_audit_key_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_audit_key_time ON public.settings_audit USING btree (setting_key, created_at DESC);


--
-- Name: idx_settings_audit_operator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_audit_operator ON public.settings_audit USING btree (operator_user, created_at DESC);


--
-- Name: idx_settings_audit_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_audit_tenant_time ON public.settings_audit USING btree (tenant_id, created_at DESC);


--
-- Name: idx_settings_kv_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_kv_category ON public.settings_kv USING btree (category);


--
-- Name: idx_settings_kv_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_kv_scope ON public.settings_kv USING btree (scope);


--
-- Name: idx_settings_kv_updated; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_kv_updated ON public.settings_kv USING btree (updated_at DESC);


--
-- Name: idx_tenant_settings_kv_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_settings_kv_category ON public.tenant_settings_kv USING btree (category);


--
-- Name: idx_tenant_settings_kv_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_settings_kv_tenant ON public.tenant_settings_kv USING btree (tenant_id);


--
-- Name: idx_tenant_subscriptions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_subscriptions_tenant ON public.tenant_subscriptions USING btree (tenant_id, status);


--
-- Name: idx_tenant_tool_policies_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_tool_policies_enabled ON public.tenant_tool_policies USING btree (enabled);


--
-- Name: idx_tenant_tool_policies_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_tool_policies_tenant ON public.tenant_tool_policies USING btree (tenant_id) WHERE (enabled = true);


--
-- Name: idx_tenants_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenants_name ON public.tenants USING btree (name);


--
-- Name: idx_tenants_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenants_status ON public.tenants USING btree (status);


--
-- Name: idx_tmp_audit_tenant_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tmp_audit_tenant_ts ON public.tenant_model_policies_audit USING btree (tenant_id, ts DESC);


--
-- Name: idx_tmp_audit_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tmp_audit_ts ON public.tenant_model_policies_audit USING btree (ts DESC);


--
-- Name: idx_tmp_canonical; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tmp_canonical ON public.tenant_model_policies USING btree (canonical_name);


--
-- Name: idx_tmp_tenant_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tmp_tenant_active ON public.tenant_model_policies USING btree (tenant_id) WHERE (deleted_at IS NULL);


--
-- Name: idx_tool_categories_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_categories_order ON public.tool_categories USING btree (display_order) WHERE (enabled = true);


--
-- Name: idx_tool_registry_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_registry_category ON public.tool_registry USING btree (category) WHERE (enabled = true);


--
-- Name: idx_tool_registry_deprecation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_registry_deprecation ON public.tool_registry USING btree (deprecation_date) WHERE (deprecation_date IS NOT NULL);


--
-- Name: idx_tool_registry_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_registry_name ON public.tool_registry USING btree (tool_name) WHERE (enabled = true);


--
-- Name: idx_tool_registry_tenant_tool; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_registry_tenant_tool ON public.tool_registry USING btree (tenant_id, tool_id, version DESC);


--
-- Name: idx_tool_registry_unique_version; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tool_registry_unique_version ON public.tool_registry USING btree (tenant_id, tool_id, version);


--
-- Name: idx_tool_stats_part_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_stats_part_created ON ONLY public.tool_usage_stats USING btree (created_at);


--
-- Name: idx_tool_stats_part_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_stats_part_date ON ONLY public.tool_usage_stats USING btree (usage_date);


--
-- Name: idx_tool_stats_part_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_stats_part_tenant ON ONLY public.tool_usage_stats USING btree (tenant_id, usage_date);


--
-- Name: idx_tool_stats_part_tool; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_stats_part_tool ON ONLY public.tool_usage_stats USING btree (tool_id, usage_date);


--
-- Name: idx_tool_usage_stats_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_usage_stats_date ON public.tool_usage_stats_old USING btree (usage_date DESC);


--
-- Name: idx_tool_usage_stats_tenant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_usage_stats_tenant_id ON public.tool_usage_stats_old USING btree (tenant_id);


--
-- Name: idx_tool_usage_stats_tool_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_usage_stats_tool_id ON public.tool_usage_stats_old USING btree (tool_id);


--
-- Name: idx_tool_usage_stats_tool_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_usage_stats_tool_tenant ON public.tool_usage_stats_old USING btree (tool_id, tenant_id, usage_date DESC);


--
-- Name: idx_tuning_proposals_cat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_proposals_cat ON public.tuning_proposals USING btree (category, task_type) WHERE (status = 'pending'::text);


--
-- Name: idx_tuning_proposals_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_proposals_created ON public.tuning_proposals USING btree (created_at) WHERE (status = 'pending'::text);


--
-- Name: idx_tuning_proposals_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_proposals_status ON public.tuning_proposals USING btree (status, ts DESC);


--
-- Name: idx_tuning_signals_5m_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tuning_signals_5m_pk ON public.tuning_signals_5m USING btree (bucket, task_type, classifier);


--
-- Name: idx_tuning_signals_5m_task_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_5m_task_ts ON public.tuning_signals_5m USING btree (task_type, classifier, bucket DESC);


--
-- Name: idx_tuning_signals_daily_pk; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_tuning_signals_daily_pk ON public.tuning_signals_daily USING btree (bucket, task_type, classifier);


--
-- Name: idx_tuning_signals_daily_task_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_daily_task_ts ON public.tuning_signals_daily USING btree (task_type, classifier, bucket DESC);


--
-- Name: idx_tuning_signals_lowq; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_lowq ON public.tuning_signals USING btree (task_type, ts DESC) WHERE ((quality_score < 0.5) AND (classifier = 'heuristic'::text));


--
-- Name: idx_tuning_signals_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_session ON public.tuning_signals USING btree (session_id, ts DESC) WHERE (session_id IS NOT NULL);


--
-- Name: idx_tuning_signals_strategy_task; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_strategy_task ON public.tuning_signals USING btree (strategy, task_type, ts DESC) WHERE (task_type IS NOT NULL);


--
-- Name: idx_tuning_signals_strategy_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_strategy_ts ON public.tuning_signals USING btree (strategy, ts DESC);


--
-- Name: idx_tuning_signals_task_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tuning_signals_task_ts ON public.tuning_signals USING btree (task_type, ts DESC);


--
-- Name: idx_usage_ledger_part_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_ledger_part_request_id ON ONLY public.usage_ledger USING btree (request_id);


--
-- Name: idx_usage_ledger_part_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_ledger_part_tenant ON ONLY public.usage_ledger USING btree (tenant_id, ts);


--
-- Name: idx_usage_ledger_part_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_ledger_part_ts ON ONLY public.usage_ledger USING btree (ts);


--
-- Name: idx_users_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_tenant ON public.users USING btree (tenant_id);


--
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_username ON public.users USING btree (username);


--
-- Name: idx_wal_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wal_session ON ONLY public.request_wal USING btree (gw_session_id, created_at);


--
-- Name: idx_wal_status_stage; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wal_status_stage ON ONLY public.request_wal USING btree (status, stage);


--
-- Name: idx_wal_tenant_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wal_tenant_created ON ONLY public.request_wal USING btree (tenant_id, created_at DESC);


--
-- Name: idx_work_type_config_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_type_config_category ON public.work_type_config USING btree (category, sort_order);


--
-- Name: idx_work_type_config_l1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_type_config_l1 ON public.work_type_config USING btree (l1_task_type);


--
-- Name: idx_wtmr_tier; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wtmr_tier ON public.work_type_model_route USING btree (work_type_key, tier, weight DESC);


--
-- Name: idx_wtmr_work_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wtmr_work_type ON public.work_type_model_route USING btree (work_type_key);


--
-- Name: request_logs_2026_06_client_model_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_client_model_idx ON public.request_logs_2026_06 USING btree (client_model);


--
-- Name: request_logs_2026_06_client_model_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_client_model_idx1 ON public.request_logs_2026_06 USING btree (client_model text_pattern_ops);


--
-- Name: request_logs_2026_06_client_model_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_client_model_idx2 ON public.request_logs_2026_06 USING hash (client_model);


--
-- Name: request_logs_2026_06_client_model_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_client_model_idx3 ON public.request_logs_2026_06 USING gin (client_model public.gin_trgm_ops);


--
-- Name: request_logs_2026_06_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_client_request_id_ts_idx ON public.request_logs_2026_06 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


--
-- Name: request_logs_2026_06_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_gw_session_id_ts_idx ON public.request_logs_2026_06 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


--
-- Name: request_logs_2026_06_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_gw_session_id_ts_idx1 ON public.request_logs_2026_06 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


--
-- Name: request_logs_2026_06_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_gw_task_id_ts_idx ON public.request_logs_2026_06 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_2026_06_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_lower_idx ON public.request_logs_2026_06 USING btree (lower(client_model));


--
-- Name: request_logs_2026_06_parent_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_parent_request_id_ts_idx ON public.request_logs_2026_06 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


--
-- Name: request_logs_2026_06_provider_id_quality_score_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_provider_id_quality_score_ts_idx ON public.request_logs_2026_06 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


--
-- Name: request_logs_2026_06_provider_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_provider_id_ts_idx ON public.request_logs_2026_06 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


--
-- Name: request_logs_2026_06_quality_flags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_quality_flags_idx ON public.request_logs_2026_06 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
-- Name: request_logs_2026_06_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX request_logs_2026_06_request_id_ts_idx ON public.request_logs_2026_06 USING btree (request_id, ts);


--
-- Name: request_logs_2026_06_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_request_status_ts_idx ON public.request_logs_2026_06 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
-- Name: request_logs_2026_06_tenant_id_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_06 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_2026_06_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_tenant_id_ts_idx ON public.request_logs_2026_06 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


--
-- Name: request_logs_2026_06_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_tenant_id_ts_idx1 ON public.request_logs_2026_06 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
-- Name: request_logs_2026_06_tool_calls_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_tool_calls_idx ON public.request_logs_2026_06 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


--
-- Name: request_logs_2026_06_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_upstream_finish_reason_ts_idx ON public.request_logs_2026_06 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


--
-- Name: request_logs_2026_06_work_type_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_work_type_ts_idx ON public.request_logs_2026_06 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


--
-- Name: request_logs_2026_07_client_model_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_client_model_idx ON public.request_logs_2026_07 USING btree (client_model);


--
-- Name: request_logs_2026_07_client_model_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_client_model_idx1 ON public.request_logs_2026_07 USING btree (client_model text_pattern_ops);


--
-- Name: request_logs_2026_07_client_model_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_client_model_idx2 ON public.request_logs_2026_07 USING hash (client_model);


--
-- Name: request_logs_2026_07_client_model_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_client_model_idx3 ON public.request_logs_2026_07 USING gin (client_model public.gin_trgm_ops);


--
-- Name: request_logs_2026_07_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_client_request_id_ts_idx ON public.request_logs_2026_07 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


--
-- Name: request_logs_2026_07_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_gw_session_id_ts_idx ON public.request_logs_2026_07 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


--
-- Name: request_logs_2026_07_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_gw_session_id_ts_idx1 ON public.request_logs_2026_07 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


--
-- Name: request_logs_2026_07_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_gw_task_id_ts_idx ON public.request_logs_2026_07 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_2026_07_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_lower_idx ON public.request_logs_2026_07 USING btree (lower(client_model));


--
-- Name: request_logs_2026_07_parent_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_parent_request_id_ts_idx ON public.request_logs_2026_07 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


--
-- Name: request_logs_2026_07_provider_id_quality_score_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_provider_id_quality_score_ts_idx ON public.request_logs_2026_07 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


--
-- Name: request_logs_2026_07_provider_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_provider_id_ts_idx ON public.request_logs_2026_07 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


--
-- Name: request_logs_2026_07_quality_flags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_quality_flags_idx ON public.request_logs_2026_07 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
-- Name: request_logs_2026_07_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX request_logs_2026_07_request_id_ts_idx ON public.request_logs_2026_07 USING btree (request_id, ts);


--
-- Name: request_logs_2026_07_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_request_status_ts_idx ON public.request_logs_2026_07 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
-- Name: request_logs_2026_07_tenant_id_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_07 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_2026_07_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_tenant_id_ts_idx ON public.request_logs_2026_07 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
-- Name: request_logs_2026_07_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_tenant_id_ts_idx1 ON public.request_logs_2026_07 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


--
-- Name: request_logs_2026_07_tool_calls_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_tool_calls_idx ON public.request_logs_2026_07 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


--
-- Name: request_logs_2026_07_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_upstream_finish_reason_ts_idx ON public.request_logs_2026_07 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


--
-- Name: request_logs_2026_07_work_type_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_work_type_ts_idx ON public.request_logs_2026_07 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


--
-- Name: request_logs_2026_08_client_model_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_model_idx ON public.request_logs_2026_08 USING btree (client_model);


--
-- Name: request_logs_2026_08_client_model_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_model_idx1 ON public.request_logs_2026_08 USING btree (client_model text_pattern_ops);


--
-- Name: request_logs_2026_08_client_model_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_model_idx2 ON public.request_logs_2026_08 USING hash (client_model);


--
-- Name: request_logs_2026_08_client_model_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_model_idx3 ON public.request_logs_2026_08 USING gin (client_model public.gin_trgm_ops);


--
-- Name: request_logs_2026_08_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_request_id_ts_idx ON public.request_logs_2026_08 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


--
-- Name: request_logs_2026_08_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_gw_session_id_ts_idx ON public.request_logs_2026_08 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


--
-- Name: request_logs_2026_08_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_gw_session_id_ts_idx1 ON public.request_logs_2026_08 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


--
-- Name: request_logs_2026_08_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_gw_task_id_ts_idx ON public.request_logs_2026_08 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_2026_08_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_lower_idx ON public.request_logs_2026_08 USING btree (lower(client_model));


--
-- Name: request_logs_2026_08_parent_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_parent_request_id_ts_idx ON public.request_logs_2026_08 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


--
-- Name: request_logs_2026_08_provider_id_quality_score_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_provider_id_quality_score_ts_idx ON public.request_logs_2026_08 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


--
-- Name: request_logs_2026_08_provider_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_provider_id_ts_idx ON public.request_logs_2026_08 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


--
-- Name: request_logs_2026_08_quality_flags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_quality_flags_idx ON public.request_logs_2026_08 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
-- Name: request_logs_2026_08_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX request_logs_2026_08_request_id_ts_idx ON public.request_logs_2026_08 USING btree (request_id, ts);


--
-- Name: request_logs_2026_08_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_request_status_ts_idx ON public.request_logs_2026_08 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
-- Name: request_logs_2026_08_tenant_id_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_08 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_2026_08_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_tenant_id_ts_idx ON public.request_logs_2026_08 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
-- Name: request_logs_2026_08_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_tenant_id_ts_idx1 ON public.request_logs_2026_08 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


--
-- Name: request_logs_2026_08_tool_calls_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_tool_calls_idx ON public.request_logs_2026_08 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


--
-- Name: request_logs_2026_08_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_upstream_finish_reason_ts_idx ON public.request_logs_2026_08 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


--
-- Name: request_logs_2026_08_work_type_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_work_type_ts_idx ON public.request_logs_2026_08 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


--
-- Name: request_logs_default_client_model_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_client_model_idx4 ON public.request_logs_default USING btree (client_model);


--
-- Name: request_logs_default_client_model_idx5; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_client_model_idx5 ON public.request_logs_default USING btree (client_model text_pattern_ops);


--
-- Name: request_logs_default_client_model_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_client_model_idx6 ON public.request_logs_default USING hash (client_model);


--
-- Name: request_logs_default_client_model_idx7; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_client_model_idx7 ON public.request_logs_default USING gin (client_model public.gin_trgm_ops);


--
-- Name: request_logs_default_client_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_client_request_id_ts_idx1 ON public.request_logs_default USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


--
-- Name: request_logs_default_gw_session_id_ts_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_gw_session_id_ts_idx2 ON public.request_logs_default USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


--
-- Name: request_logs_default_gw_session_id_ts_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_gw_session_id_ts_idx3 ON public.request_logs_default USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


--
-- Name: request_logs_default_gw_task_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_gw_task_id_ts_idx1 ON public.request_logs_default USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_default_lower_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_lower_idx1 ON public.request_logs_default USING btree (lower(client_model));


--
-- Name: request_logs_default_parent_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_parent_request_id_ts_idx1 ON public.request_logs_default USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


--
-- Name: request_logs_default_provider_id_quality_score_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_provider_id_quality_score_ts_idx1 ON public.request_logs_default USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


--
-- Name: request_logs_default_provider_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_provider_id_ts_idx1 ON public.request_logs_default USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


--
-- Name: request_logs_default_quality_flags_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_quality_flags_idx1 ON public.request_logs_default USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
-- Name: request_logs_default_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX request_logs_default_request_id_ts_idx1 ON public.request_logs_default USING btree (request_id, ts);


--
-- Name: request_logs_default_request_status_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_request_status_ts_idx1 ON public.request_logs_default USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


--
-- Name: request_logs_default_tenant_id_gw_task_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tenant_id_gw_task_id_ts_idx1 ON public.request_logs_default USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
-- Name: request_logs_default_tenant_id_ts_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tenant_id_ts_idx2 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


--
-- Name: request_logs_default_tenant_id_ts_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tenant_id_ts_idx3 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
-- Name: request_logs_default_tool_calls_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tool_calls_idx1 ON public.request_logs_default USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


--
-- Name: request_logs_default_upstream_finish_reason_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_upstream_finish_reason_ts_idx1 ON public.request_logs_default USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


--
-- Name: request_logs_default_work_type_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_work_type_ts_idx1 ON public.request_logs_default USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


--
-- Name: request_wal_2026_06_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_06_gw_session_id_created_at_idx ON public.request_wal_2026_06 USING btree (gw_session_id, created_at);


--
-- Name: request_wal_2026_06_status_stage_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_06_status_stage_idx ON public.request_wal_2026_06 USING btree (status, stage);


--
-- Name: request_wal_2026_06_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_06_tenant_id_created_at_idx ON public.request_wal_2026_06 USING btree (tenant_id, created_at DESC);


--
-- Name: request_wal_2026_07_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_07_gw_session_id_created_at_idx ON public.request_wal_2026_07 USING btree (gw_session_id, created_at);


--
-- Name: request_wal_2026_07_status_stage_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_07_status_stage_idx ON public.request_wal_2026_07 USING btree (status, stage);


--
-- Name: request_wal_2026_07_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_wal_2026_07_tenant_id_created_at_idx ON public.request_wal_2026_07 USING btree (tenant_id, created_at DESC);


--
-- Name: routing_decision_log_2026_06_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_06 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--
-- Name: routing_decision_log_2026_06_model_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_model_ts_idx ON public.routing_decision_log_2026_06 USING btree (model, ts DESC);


--
-- Name: routing_decision_log_2026_06_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_request_id_idx ON public.routing_decision_log_2026_06 USING btree (request_id);


--
-- Name: routing_decision_log_2026_06_success_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_success_ts_idx ON public.routing_decision_log_2026_06 USING btree (success, ts DESC);


--
-- Name: routing_decision_log_2026_06_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_tenant_id_ts_idx ON public.routing_decision_log_2026_06 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--
-- Name: routing_decision_log_2026_06_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_ts_idx ON public.routing_decision_log_2026_06 USING btree (ts DESC);


--
-- Name: routing_decision_log_2026_07_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--
-- Name: routing_decision_log_2026_07_model_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_model_ts_idx ON public.routing_decision_log_2026_07 USING btree (model, ts DESC);


--
-- Name: routing_decision_log_2026_07_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_request_id_idx ON public.routing_decision_log_2026_07 USING btree (request_id);


--
-- Name: routing_decision_log_2026_07_success_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_success_ts_idx ON public.routing_decision_log_2026_07 USING btree (success, ts DESC);


--
-- Name: routing_decision_log_2026_07_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_tenant_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--
-- Name: routing_decision_log_2026_07_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_ts_idx ON public.routing_decision_log_2026_07 USING btree (ts DESC);


--
-- Name: routing_decision_log_default_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_chosen_credential_id_ts_idx ON public.routing_decision_log_default USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--
-- Name: routing_decision_log_default_model_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_model_ts_idx ON public.routing_decision_log_default USING btree (model, ts DESC);


--
-- Name: routing_decision_log_default_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_request_id_idx ON public.routing_decision_log_default USING btree (request_id);


--
-- Name: routing_decision_log_default_success_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_success_ts_idx ON public.routing_decision_log_default USING btree (success, ts DESC);


--
-- Name: routing_decision_log_default_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_tenant_id_ts_idx ON public.routing_decision_log_default USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--
-- Name: routing_decision_log_default_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_ts_idx ON public.routing_decision_log_default USING btree (ts DESC);


--
-- Name: tool_usage_stats_2026_06_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_06_created_at_idx ON public.tool_usage_stats_2026_06 USING btree (created_at);


--
-- Name: tool_usage_stats_2026_06_tenant_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_06_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (tenant_id, usage_date);


--
-- Name: tool_usage_stats_2026_06_tool_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_06_tool_id_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (tool_id, usage_date);


--
-- Name: tool_usage_stats_2026_06_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_06_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (usage_date);


--
-- Name: tool_usage_stats_2026_07_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_07_created_at_idx ON public.tool_usage_stats_2026_07 USING btree (created_at);


--
-- Name: tool_usage_stats_2026_07_tenant_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_07_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (tenant_id, usage_date);


--
-- Name: tool_usage_stats_2026_07_tool_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_07_tool_id_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (tool_id, usage_date);


--
-- Name: tool_usage_stats_2026_07_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_07_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (usage_date);


--
-- Name: tool_usage_stats_2026_08_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_08_created_at_idx ON public.tool_usage_stats_2026_08 USING btree (created_at);


--
-- Name: tool_usage_stats_2026_08_tenant_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_08_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tenant_id, usage_date);


--
-- Name: tool_usage_stats_2026_08_tool_id_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_08_tool_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tool_id, usage_date);


--
-- Name: tool_usage_stats_2026_08_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_08_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (usage_date);


--
-- Name: usage_ledger_2026_06_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_06_request_id_idx ON public.usage_ledger_2026_06 USING btree (request_id);


--
-- Name: usage_ledger_2026_06_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_06_tenant_id_ts_idx ON public.usage_ledger_2026_06 USING btree (tenant_id, ts);


--
-- Name: usage_ledger_2026_06_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_06_ts_idx ON public.usage_ledger_2026_06 USING btree (ts);


--
-- Name: usage_ledger_2026_07_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_07_request_id_idx ON public.usage_ledger_2026_07 USING btree (request_id);


--
-- Name: usage_ledger_2026_07_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_07_tenant_id_ts_idx ON public.usage_ledger_2026_07 USING btree (tenant_id, ts);


--
-- Name: usage_ledger_2026_07_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_07_ts_idx ON public.usage_ledger_2026_07 USING btree (ts);


--
-- Name: usage_ledger_2026_08_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_08_request_id_idx ON public.usage_ledger_2026_08 USING btree (request_id);


--
-- Name: usage_ledger_2026_08_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_08_tenant_id_ts_idx ON public.usage_ledger_2026_08 USING btree (tenant_id, ts);


--
-- Name: usage_ledger_2026_08_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX usage_ledger_2026_08_ts_idx ON public.usage_ledger_2026_08 USING btree (ts);


--
-- Name: credential_model_index_archiv_credential_id_raw_model_bucke_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_cred_model ATTACH PARTITION public.credential_model_index_archiv_credential_id_raw_model_bucke_idx;


--
-- Name: credential_model_index_archive_2026_06_bucket_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_bucket ATTACH PARTITION public.credential_model_index_archive_2026_06_bucket_idx;


--
-- Name: credential_model_index_archive_2026_06_canonical_id_bucket_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_canonical ATTACH PARTITION public.credential_model_index_archive_2026_06_canonical_id_bucket_idx;


--
-- Name: credit_ledger_2026_06_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_06_created_at_idx;


--
-- Name: credit_ledger_2026_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_06_pkey;


--
-- Name: credit_ledger_2026_06_ref_type_ref_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_06_ref_type_ref_id_idx;


--
-- Name: credit_ledger_2026_06_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_06_tenant_id_created_at_idx;


--
-- Name: credit_ledger_2026_07_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_07_created_at_idx;


--
-- Name: credit_ledger_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_07_pkey;


--
-- Name: credit_ledger_2026_07_ref_type_ref_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_07_ref_type_ref_id_idx;


--
-- Name: credit_ledger_2026_07_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_07_tenant_id_created_at_idx;


--
-- Name: credit_ledger_2026_08_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_08_created_at_idx;


--
-- Name: credit_ledger_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_08_pkey;


--
-- Name: credit_ledger_2026_08_ref_type_ref_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_08_ref_type_ref_id_idx;


--
-- Name: credit_ledger_2026_08_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_08_tenant_id_created_at_idx;


--
-- Name: request_logs_2026_06_client_model_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_2026_06_client_model_idx;


--
-- Name: request_logs_2026_06_client_model_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_2026_06_client_model_idx1;


--
-- Name: request_logs_2026_06_client_model_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_2026_06_client_model_idx2;


--
-- Name: request_logs_2026_06_client_model_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_trgm ATTACH PARTITION public.request_logs_2026_06_client_model_idx3;


--
-- Name: request_logs_2026_06_client_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_2026_06_client_request_id_ts_idx;


--
-- Name: request_logs_2026_06_gw_session_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_2026_06_gw_session_id_ts_idx;


--
-- Name: request_logs_2026_06_gw_session_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_2026_06_gw_session_id_ts_idx1;


--
-- Name: request_logs_2026_06_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_2026_06_gw_task_id_ts_idx;


--
-- Name: request_logs_2026_06_lower_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_2026_06_lower_idx;


--
-- Name: request_logs_2026_06_parent_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_2026_06_parent_request_id_ts_idx;


--
-- Name: request_logs_2026_06_provider_id_quality_score_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_2026_06_provider_id_quality_score_ts_idx;


--
-- Name: request_logs_2026_06_provider_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_2026_06_provider_id_ts_idx;


--
-- Name: request_logs_2026_06_quality_flags_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_2026_06_quality_flags_idx;


--
-- Name: request_logs_2026_06_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_2026_06_request_id_ts_idx;


--
-- Name: request_logs_2026_06_request_status_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_2026_06_request_status_ts_idx;


--
-- Name: request_logs_2026_06_tenant_id_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_2026_06_tenant_id_gw_task_id_ts_idx;


--
-- Name: request_logs_2026_06_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_2026_06_tenant_id_ts_idx;


--
-- Name: request_logs_2026_06_tenant_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_2026_06_tenant_id_ts_idx1;


--
-- Name: request_logs_2026_06_tool_calls_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_2026_06_tool_calls_idx;


--
-- Name: request_logs_2026_06_upstream_finish_reason_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_2026_06_upstream_finish_reason_ts_idx;


--
-- Name: request_logs_2026_06_work_type_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_2026_06_work_type_ts_idx;


--
-- Name: request_logs_2026_07_client_model_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_2026_07_client_model_idx;


--
-- Name: request_logs_2026_07_client_model_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_2026_07_client_model_idx1;


--
-- Name: request_logs_2026_07_client_model_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_2026_07_client_model_idx2;


--
-- Name: request_logs_2026_07_client_model_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_trgm ATTACH PARTITION public.request_logs_2026_07_client_model_idx3;


--
-- Name: request_logs_2026_07_client_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_2026_07_client_request_id_ts_idx;


--
-- Name: request_logs_2026_07_gw_session_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_2026_07_gw_session_id_ts_idx;


--
-- Name: request_logs_2026_07_gw_session_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_2026_07_gw_session_id_ts_idx1;


--
-- Name: request_logs_2026_07_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_2026_07_gw_task_id_ts_idx;


--
-- Name: request_logs_2026_07_lower_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_2026_07_lower_idx;


--
-- Name: request_logs_2026_07_parent_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_2026_07_parent_request_id_ts_idx;


--
-- Name: request_logs_2026_07_provider_id_quality_score_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_2026_07_provider_id_quality_score_ts_idx;


--
-- Name: request_logs_2026_07_provider_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_2026_07_provider_id_ts_idx;


--
-- Name: request_logs_2026_07_quality_flags_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_2026_07_quality_flags_idx;


--
-- Name: request_logs_2026_07_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_2026_07_request_id_ts_idx;


--
-- Name: request_logs_2026_07_request_status_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_2026_07_request_status_ts_idx;


--
-- Name: request_logs_2026_07_tenant_id_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_2026_07_tenant_id_gw_task_id_ts_idx;


--
-- Name: request_logs_2026_07_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_2026_07_tenant_id_ts_idx;


--
-- Name: request_logs_2026_07_tenant_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_2026_07_tenant_id_ts_idx1;


--
-- Name: request_logs_2026_07_tool_calls_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_2026_07_tool_calls_idx;


--
-- Name: request_logs_2026_07_upstream_finish_reason_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_2026_07_upstream_finish_reason_ts_idx;


--
-- Name: request_logs_2026_07_work_type_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_2026_07_work_type_ts_idx;


--
-- Name: request_logs_2026_08_client_model_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_2026_08_client_model_idx;


--
-- Name: request_logs_2026_08_client_model_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_2026_08_client_model_idx1;


--
-- Name: request_logs_2026_08_client_model_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_2026_08_client_model_idx2;


--
-- Name: request_logs_2026_08_client_model_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_trgm ATTACH PARTITION public.request_logs_2026_08_client_model_idx3;


--
-- Name: request_logs_2026_08_client_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_2026_08_client_request_id_ts_idx;


--
-- Name: request_logs_2026_08_gw_session_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_2026_08_gw_session_id_ts_idx;


--
-- Name: request_logs_2026_08_gw_session_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_2026_08_gw_session_id_ts_idx1;


--
-- Name: request_logs_2026_08_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_2026_08_gw_task_id_ts_idx;


--
-- Name: request_logs_2026_08_lower_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_2026_08_lower_idx;


--
-- Name: request_logs_2026_08_parent_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_2026_08_parent_request_id_ts_idx;


--
-- Name: request_logs_2026_08_provider_id_quality_score_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_2026_08_provider_id_quality_score_ts_idx;


--
-- Name: request_logs_2026_08_provider_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_2026_08_provider_id_ts_idx;


--
-- Name: request_logs_2026_08_quality_flags_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_2026_08_quality_flags_idx;


--
-- Name: request_logs_2026_08_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_2026_08_request_id_ts_idx;


--
-- Name: request_logs_2026_08_request_status_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_2026_08_request_status_ts_idx;


--
-- Name: request_logs_2026_08_tenant_id_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_2026_08_tenant_id_gw_task_id_ts_idx;


--
-- Name: request_logs_2026_08_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_2026_08_tenant_id_ts_idx;


--
-- Name: request_logs_2026_08_tenant_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_2026_08_tenant_id_ts_idx1;


--
-- Name: request_logs_2026_08_tool_calls_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_2026_08_tool_calls_idx;


--
-- Name: request_logs_2026_08_upstream_finish_reason_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_2026_08_upstream_finish_reason_ts_idx;


--
-- Name: request_logs_2026_08_work_type_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_2026_08_work_type_ts_idx;


--
-- Name: request_logs_default_client_model_idx4; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_default_client_model_idx4;


--
-- Name: request_logs_default_client_model_idx5; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_default_client_model_idx5;


--
-- Name: request_logs_default_client_model_idx6; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_default_client_model_idx6;


--
-- Name: request_logs_default_client_model_idx7; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_trgm ATTACH PARTITION public.request_logs_default_client_model_idx7;


--
-- Name: request_logs_default_client_request_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_default_client_request_id_ts_idx1;


--
-- Name: request_logs_default_gw_session_id_ts_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_default_gw_session_id_ts_idx2;


--
-- Name: request_logs_default_gw_session_id_ts_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_default_gw_session_id_ts_idx3;


--
-- Name: request_logs_default_gw_task_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_default_gw_task_id_ts_idx1;


--
-- Name: request_logs_default_lower_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_default_lower_idx1;


--
-- Name: request_logs_default_parent_request_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_default_parent_request_id_ts_idx1;


--
-- Name: request_logs_default_provider_id_quality_score_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_default_provider_id_quality_score_ts_idx1;


--
-- Name: request_logs_default_provider_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_default_provider_id_ts_idx1;


--
-- Name: request_logs_default_quality_flags_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_default_quality_flags_idx1;


--
-- Name: request_logs_default_request_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_default_request_id_ts_idx1;


--
-- Name: request_logs_default_request_status_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_default_request_status_ts_idx1;


--
-- Name: request_logs_default_tenant_id_gw_task_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_default_tenant_id_gw_task_id_ts_idx1;


--
-- Name: request_logs_default_tenant_id_ts_idx2; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_default_tenant_id_ts_idx2;


--
-- Name: request_logs_default_tenant_id_ts_idx3; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_default_tenant_id_ts_idx3;


--
-- Name: request_logs_default_tool_calls_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_default_tool_calls_idx1;


--
-- Name: request_logs_default_upstream_finish_reason_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_default_upstream_finish_reason_ts_idx1;


--
-- Name: request_logs_default_work_type_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_default_work_type_ts_idx1;


--
-- Name: request_wal_2026_06_gw_session_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_06_gw_session_id_created_at_idx;


--
-- Name: request_wal_2026_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_06_pkey;


--
-- Name: request_wal_2026_06_status_stage_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_06_status_stage_idx;


--
-- Name: request_wal_2026_06_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_06_tenant_id_created_at_idx;


--
-- Name: request_wal_2026_07_gw_session_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_07_gw_session_id_created_at_idx;


--
-- Name: request_wal_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_07_pkey;


--
-- Name: request_wal_2026_07_status_stage_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_07_status_stage_idx;


--
-- Name: request_wal_2026_07_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_07_tenant_id_created_at_idx;


--
-- Name: routing_decision_log_2026_06_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_06_chosen_credential_id_ts_idx;


--
-- Name: routing_decision_log_2026_06_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_06_model_ts_idx;


--
-- Name: routing_decision_log_2026_06_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_06_request_id_idx;


--
-- Name: routing_decision_log_2026_06_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_06_success_ts_idx;


--
-- Name: routing_decision_log_2026_06_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_06_tenant_id_ts_idx;


--
-- Name: routing_decision_log_2026_06_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_06_ts_idx;


--
-- Name: routing_decision_log_2026_07_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_07_chosen_credential_id_ts_idx;


--
-- Name: routing_decision_log_2026_07_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_07_model_ts_idx;


--
-- Name: routing_decision_log_2026_07_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_07_request_id_idx;


--
-- Name: routing_decision_log_2026_07_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_07_success_ts_idx;


--
-- Name: routing_decision_log_2026_07_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_07_tenant_id_ts_idx;


--
-- Name: routing_decision_log_2026_07_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_07_ts_idx;


--
-- Name: routing_decision_log_default_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_default_chosen_credential_id_ts_idx;


--
-- Name: routing_decision_log_default_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_default_model_ts_idx;


--
-- Name: routing_decision_log_default_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_default_request_id_idx;


--
-- Name: routing_decision_log_default_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_default_success_ts_idx;


--
-- Name: routing_decision_log_default_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_default_tenant_id_ts_idx;


--
-- Name: routing_decision_log_default_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_default_ts_idx;


--
-- Name: tool_usage_stats_2026_06_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_06_created_at_idx;


--
-- Name: tool_usage_stats_2026_06_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_06_pkey;


--
-- Name: tool_usage_stats_2026_06_tenant_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_06_tenant_id_usage_date_idx;


--
-- Name: tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key;


--
-- Name: tool_usage_stats_2026_06_tool_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_usage_date_idx;


--
-- Name: tool_usage_stats_2026_06_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_06_usage_date_idx;


--
-- Name: tool_usage_stats_2026_07_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_07_created_at_idx;


--
-- Name: tool_usage_stats_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_07_pkey;


--
-- Name: tool_usage_stats_2026_07_tenant_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_07_tenant_id_usage_date_idx;


--
-- Name: tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key;


--
-- Name: tool_usage_stats_2026_07_tool_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_07_tool_id_usage_date_idx;


--
-- Name: tool_usage_stats_2026_07_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_07_usage_date_idx;


--
-- Name: tool_usage_stats_2026_08_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_08_created_at_idx;


--
-- Name: tool_usage_stats_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_08_pkey;


--
-- Name: tool_usage_stats_2026_08_tenant_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_08_tenant_id_usage_date_idx;


--
-- Name: tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key;


--
-- Name: tool_usage_stats_2026_08_tool_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_08_tool_id_usage_date_idx;


--
-- Name: tool_usage_stats_2026_08_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_08_usage_date_idx;


--
-- Name: usage_ledger_2026_06_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_request_id ATTACH PARTITION public.usage_ledger_2026_06_request_id_idx;


--
-- Name: usage_ledger_2026_06_request_id_ts_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_2026_06_request_id_ts_key;


--
-- Name: usage_ledger_2026_06_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_2026_06_tenant_id_ts_idx;


--
-- Name: usage_ledger_2026_06_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_ts ATTACH PARTITION public.usage_ledger_2026_06_ts_idx;


--
-- Name: usage_ledger_2026_07_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_request_id ATTACH PARTITION public.usage_ledger_2026_07_request_id_idx;


--
-- Name: usage_ledger_2026_07_request_id_ts_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_2026_07_request_id_ts_key;


--
-- Name: usage_ledger_2026_07_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_2026_07_tenant_id_ts_idx;


--
-- Name: usage_ledger_2026_07_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_ts ATTACH PARTITION public.usage_ledger_2026_07_ts_idx;


--
-- Name: usage_ledger_2026_08_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_request_id ATTACH PARTITION public.usage_ledger_2026_08_request_id_idx;


--
-- Name: usage_ledger_2026_08_request_id_ts_key; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_2026_08_request_id_ts_key;


--
-- Name: usage_ledger_2026_08_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_2026_08_tenant_id_ts_idx;


--
-- Name: usage_ledger_2026_08_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_usage_ledger_part_ts ATTACH PARTITION public.usage_ledger_2026_08_ts_idx;


--
-- Name: credential_model_bindings cmb_protect_manual_disable; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER cmb_protect_manual_disable BEFORE UPDATE ON public.credential_model_bindings FOR EACH ROW EXECUTE FUNCTION public.trg_cmb_protect_manual_disable();


--
-- Name: model_offers model_offers_delete; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER model_offers_delete INSTEAD OF DELETE ON public.model_offers FOR EACH ROW EXECUTE FUNCTION public.model_offers_delete_trigger();


--
-- Name: model_offers model_offers_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER model_offers_insert INSTEAD OF INSERT ON public.model_offers FOR EACH ROW EXECUTE FUNCTION public.model_offers_insert_trigger();


--
-- Name: model_offers model_offers_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER model_offers_update INSTEAD OF UPDATE ON public.model_offers FOR EACH ROW EXECUTE FUNCTION public.model_offers_update_trigger();


--
-- Name: routing_overrides routing_overrides_audit_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER routing_overrides_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.routing_overrides FOR EACH ROW EXECUTE FUNCTION public.routing_overrides_audit_fn();


--
-- Name: session_audit_records session_audit_records_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER session_audit_records_updated_at BEFORE UPDATE ON public.session_audit_records FOR EACH ROW EXECUTE FUNCTION public.trg_session_audit_records_updated_at();


--
-- Name: tenant_model_policies tenant_model_policies_audit_trg; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER tenant_model_policies_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.tenant_model_policies FOR EACH ROW EXECUTE FUNCTION public.tenant_model_policies_audit_fn();


--
-- Name: credentials trg_auto_fp_slot_limit_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_auto_fp_slot_limit_insert BEFORE INSERT ON public.credentials FOR EACH ROW EXECUTE FUNCTION public.auto_set_fp_slot_limit();


--
-- Name: credentials trg_check_credential_dates; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_check_credential_dates BEFORE INSERT OR UPDATE ON public.credentials FOR EACH ROW EXECUTE FUNCTION public.check_credential_dates();


--
-- Name: key_applications trg_key_applications_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_key_applications_updated_at BEFORE UPDATE ON public.key_applications FOR EACH ROW EXECUTE FUNCTION public.key_applications_set_updated_at();


--
-- Name: api_keys trg_notify_auto_route_apikeys; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_auto_route_apikeys AFTER UPDATE OF rate_limit_rpm, budget_usd, enabled, status ON public.api_keys FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();


--
-- Name: credential_model_bindings trg_notify_auto_route_cmb; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_auto_route_cmb AFTER INSERT OR DELETE OR UPDATE ON public.credential_model_bindings FOR EACH ROW EXECUTE FUNCTION public.notify_auto_route_refresh();


--
-- Name: credentials trg_notify_auto_route_creds; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_auto_route_creds AFTER UPDATE OF status, availability_state, quota_state, circuit_state, concurrency_limit, lifecycle_status, manual_disabled ON public.credentials FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();


--
-- Name: providers trg_notify_auto_route_providers; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_notify_auto_route_providers AFTER UPDATE OF enabled, manual_disabled ON public.providers FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();


--
-- Name: request_logs trg_update_api_key_model_cost; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trg_update_api_key_model_cost AFTER INSERT ON public.request_logs FOR EACH ROW WHEN ((new.is_auto_request = true)) EXECUTE FUNCTION public.update_api_key_model_cost();


--
-- Name: provider_settings trigger_provider_settings_updated_at; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER trigger_provider_settings_updated_at BEFORE UPDATE ON public.provider_settings FOR EACH ROW EXECUTE FUNCTION public.update_provider_settings_updated_at();


--
-- Name: agent_relationships fk_agent_rel_dst; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT fk_agent_rel_dst FOREIGN KEY (dst_agent_id) REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: agent_relationships fk_agent_rel_src; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT fk_agent_rel_src FOREIGN KEY (src_agent_id) REFERENCES public.agents(id) ON DELETE CASCADE;


--
-- Name: asset_relationships fk_asset_rel_dst; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT fk_asset_rel_dst FOREIGN KEY (dst_kind, dst_ref_id) REFERENCES public.assets(kind, ref_id) ON DELETE CASCADE;


--
-- Name: asset_relationships fk_asset_rel_src; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT fk_asset_rel_src FOREIGN KEY (src_kind, src_ref_id) REFERENCES public.assets(kind, ref_id) ON DELETE CASCADE;


--
-- Name: output_compliance_policies fk_output_compliance_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT fk_output_compliance_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;


--
-- Name: prompt_injection_policies fk_prompt_injection_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT fk_prompt_injection_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;


--
-- Name: session_summaries fk_session_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT fk_session_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;


--
-- Name: prompt_injection_detections prompt_injection_detections_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_detections
    ADD CONSTRAINT prompt_injection_detections_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES public.prompt_injection_rules(id) ON DELETE SET NULL;


--
-- Name: agent_relationships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agent_relationships ENABLE ROW LEVEL SECURITY;

--
-- Name: agents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;

--
-- Name: approval_queue; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.approval_queue ENABLE ROW LEVEL SECURITY;

--
-- Name: armor_judgments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.armor_judgments ENABLE ROW LEVEL SECURITY;

--
-- Name: asset_relationships; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.asset_relationships ENABLE ROW LEVEL SECURITY;

--
-- Name: assets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;

--
-- Name: billing_orders; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.billing_orders ENABLE ROW LEVEL SECURITY;

--
-- Name: credit_ledger_old; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.credit_ledger_old ENABLE ROW LEVEL SECURITY;

--
-- Name: output_compliance_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.output_compliance_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: output_compliance_audit output_compliance_audit_super_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY output_compliance_audit_super_admin ON public.output_compliance_audit USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


--
-- Name: output_compliance_audit output_compliance_audit_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY output_compliance_audit_tenant ON public.output_compliance_audit USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
-- Name: output_compliance_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.output_compliance_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: output_compliance_policies output_compliance_policies_super_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY output_compliance_policies_super_admin ON public.output_compliance_policies USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


--
-- Name: output_compliance_policies output_compliance_policies_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY output_compliance_policies_tenant ON public.output_compliance_policies USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
-- Name: prompt_injection_detections; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.prompt_injection_detections ENABLE ROW LEVEL SECURITY;

--
-- Name: prompt_injection_detections prompt_injection_detections_super_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY prompt_injection_detections_super_admin ON public.prompt_injection_detections USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


--
-- Name: prompt_injection_detections prompt_injection_detections_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY prompt_injection_detections_tenant ON public.prompt_injection_detections USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
-- Name: prompt_injection_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.prompt_injection_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: prompt_injection_policies prompt_injection_policies_super_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY prompt_injection_policies_super_admin ON public.prompt_injection_policies USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


--
-- Name: prompt_injection_policies prompt_injection_policies_tenant; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY prompt_injection_policies_tenant ON public.prompt_injection_policies USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
-- Name: request_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.request_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: request_logs_archive; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.request_logs_archive ENABLE ROW LEVEL SECURITY;

--
-- Name: response_format_anomalies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.response_format_anomalies ENABLE ROW LEVEL SECURITY;

--
-- Name: response_format_anomalies response_format_anomalies_super_admin; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY response_format_anomalies_super_admin ON public.response_format_anomalies USING ((current_setting('app.bypass_rls'::text, true) = 'true'::text));


--
-- Name: response_format_anomalies response_format_anomalies_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY response_format_anomalies_tenant_isolation ON public.response_format_anomalies USING (((tenant_id IS NULL) OR (tenant_id = public.get_current_tenant())));


--
-- Name: routing_decision_log_archive; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.routing_decision_log_archive ENABLE ROW LEVEL SECURITY;

--
-- Name: session_audit_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.session_audit_records ENABLE ROW LEVEL SECURITY;

--
-- Name: session_summaries; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.session_summaries ENABLE ROW LEVEL SECURITY;

--
-- Name: session_summaries session_summaries_super_admin_bypass; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY session_summaries_super_admin_bypass ON public.session_summaries USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


--
-- Name: session_summaries session_summaries_tenant_isolation; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY session_summaries_tenant_isolation ON public.session_summaries USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));


--
-- Name: settings_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.settings_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_credit_wallets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_credit_wallets ENABLE ROW LEVEL SECURITY;

--
-- Name: agent_relationships tenant_isolation_agent_relationships; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_agent_relationships ON public.agent_relationships USING (((EXISTS ( SELECT 1
   FROM public.agents a_src
  WHERE ((a_src.id = agent_relationships.src_agent_id) AND (a_src.tenant_id = public.get_current_tenant())))) AND (EXISTS ( SELECT 1
   FROM public.agents a_dst
  WHERE ((a_dst.id = agent_relationships.dst_agent_id) AND (a_dst.tenant_id = public.get_current_tenant()))))));


--
-- Name: agents tenant_isolation_agents; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_agents ON public.agents USING ((tenant_id = public.get_current_tenant()));


--
-- Name: approval_queue tenant_isolation_approval_queue; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_approval_queue ON public.approval_queue USING (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text)))) WITH CHECK (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text))));


--
-- Name: armor_judgments tenant_isolation_armor_judgments; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_armor_judgments ON public.armor_judgments USING ((tenant_id = public.get_current_tenant()));


--
-- Name: asset_relationships tenant_isolation_asset_relationships; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_asset_relationships ON public.asset_relationships USING (((EXISTS ( SELECT 1
   FROM public.assets a_src
  WHERE ((a_src.kind = asset_relationships.src_kind) AND (a_src.ref_id = asset_relationships.src_ref_id) AND (a_src.tenant_id = public.get_current_tenant())))) AND (EXISTS ( SELECT 1
   FROM public.assets a_dst
  WHERE ((a_dst.kind = asset_relationships.dst_kind) AND (a_dst.ref_id = asset_relationships.dst_ref_id) AND (a_dst.tenant_id = public.get_current_tenant()))))));


--
-- Name: assets tenant_isolation_assets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_assets ON public.assets USING ((tenant_id = public.get_current_tenant()));


--
-- Name: billing_orders tenant_isolation_billing_orders; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_billing_orders ON public.billing_orders USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: credit_ledger_old tenant_isolation_credit_ledger; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_credit_ledger ON public.credit_ledger_old USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: request_logs tenant_isolation_request_logs; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_request_logs ON public.request_logs USING ((tenant_id = public.get_current_tenant()));


--
-- Name: request_logs_archive tenant_isolation_request_logs_archive; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_request_logs_archive ON public.request_logs_archive USING ((tenant_id = public.get_current_tenant()));


--
-- Name: routing_decision_log_archive tenant_isolation_routing_decision_log_archive; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive USING ((tenant_id = public.get_current_tenant()));


--
-- Name: session_audit_records tenant_isolation_session_audit_records; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_session_audit_records ON public.session_audit_records USING (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text)))) WITH CHECK (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text))));


--
-- Name: settings_audit tenant_isolation_settings_audit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_settings_audit ON public.settings_audit USING ((((tenant_id)::text = public.get_current_tenant()) OR (tenant_id IS NULL)));


--
-- Name: tenant_credit_wallets tenant_isolation_tenant_credit_wallets; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tenant_credit_wallets ON public.tenant_credit_wallets USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tenant_settings_kv tenant_isolation_tenant_settings_kv; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tenant_settings_kv ON public.tenant_settings_kv USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tenant_subscriptions tenant_isolation_tenant_subscriptions; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tenant_subscriptions ON public.tenant_subscriptions USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tenant_tool_policies tenant_isolation_tenant_tool_policies; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tenant_tool_policies ON public.tenant_tool_policies USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tenant_model_policies tenant_isolation_tmp; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tmp ON public.tenant_model_policies USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tenant_model_policies_audit tenant_isolation_tmp_audit; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tmp_audit ON public.tenant_model_policies_audit USING (((tenant_id = public.get_current_tenant()) OR (tenant_id IS NULL)));


--
-- Name: tool_call_events tenant_isolation_tool_call_events; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tool_call_events ON public.tool_call_events USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tool_registry tenant_isolation_tool_registry; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tool_registry ON public.tool_registry USING ((((tenant_id)::text = public.get_current_tenant()) OR (tenant_id IS NULL) OR ((tenant_id)::text = 'default'::text)));


--
-- Name: tool_usage_stats tenant_isolation_tool_usage_stats; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tool_usage_stats ON public.tool_usage_stats USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tool_usage_stats_old tenant_isolation_tool_usage_stats; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_tool_usage_stats ON public.tool_usage_stats_old USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: users tenant_isolation_users; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_users ON public.users USING (((tenant_id)::text = public.get_current_tenant()));


--
-- Name: tenant_model_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_model_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_model_policies_audit; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_model_policies_audit ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_settings_kv; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_settings_kv ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: tenant_tool_policies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tenant_tool_policies ENABLE ROW LEVEL SECURITY;

--
-- Name: tool_call_events; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tool_call_events ENABLE ROW LEVEL SECURITY;

--
-- Name: tool_registry; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tool_registry ENABLE ROW LEVEL SECURITY;

--
-- Name: tool_usage_stats; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tool_usage_stats ENABLE ROW LEVEL SECURITY;

--
-- Name: tool_usage_stats_old; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.tool_usage_stats_old ENABLE ROW LEVEL SECURITY;

--
-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

--
-- PostgreSQL database dump complete
--

\unrestrict 4ey3UQUuyKB95a0ZOSRup1DCQroXHnLJZhA7aKDSzpkTqeL56r6HaeBBbwhY9qo

