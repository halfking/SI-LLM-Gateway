-- ============================================
-- Function: ensure_routing_decision_log_partition
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.ensure_routing_decision_log_partition(target_month timestamp with time zone) RETURNS void
    LANGUAGE plpgsql
    AS $$
DECLARE
    month_start date := date_trunc('month', target_month)::date;
    month_end   date := (date_trunc('month', target_month) + interval '1 month')::date;
    partition_name text := 'routing_decision_log_' || to_char(month_start, 'YYYY_MM');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_class
                   WHERE relname = partition_name
                     AND relnamespace = 'public'::regnamespace) THEN
        EXECUTE format(
            'CREATE TABLE %I PARTITION OF routing_decision_log
             FOR VALUES FROM (%L) TO (%L)',
            partition_name, month_start, month_end
        );
        RAISE NOTICE 'Created partition % for routing_decision_log', partition_name;
    END IF;
END;
$$;



COMMENT ON FUNCTION public.ensure_routing_decision_log_partition(target_month timestamp with time zone) IS 'Ensure a monthly partition exists for routing_decision_log at the given month.
Called by bg.PartitionManager on every tick for current + next month.
Idempotent. Added 2026-06-30 in migration 319.';



