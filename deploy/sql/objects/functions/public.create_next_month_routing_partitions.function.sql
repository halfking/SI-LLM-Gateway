-- ===========================================================================
-- Object:   create_next_month_routing_partitions()
-- Type:     FUNCTION
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
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
