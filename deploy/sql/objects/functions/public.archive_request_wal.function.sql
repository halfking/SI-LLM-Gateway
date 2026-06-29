-- ===========================================================================
-- Object:   archive_request_wal(date)
-- Type:     FUNCTION
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: archive_request_wal(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_request_wal(archive_month date) RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
    AS $$ DECLARE month_start date := date_trunc('month', archive_month)::date; month_end date := (date_trunc('month', archive_month) + interval '1 month')::date; src_part text := 'request_wal_' || to_char(month_start, 'YYYY_MM'); dst_part text := 'request_wal_archive_' || to_char(month_start, 'YYYY_MM'); row_count bigint; partition_existed boolean := false; col_list text; BEGIN IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN RETURN QUERY SELECT 'skipped'::text, 0::bigint, false; RETURN; END IF; partition_existed := true; IF NOT EXISTS (SELECT 1 FROM pg_class WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN EXECUTE format('CREATE TABLE %I PARTITION OF request_wal_archive FOR VALUES FROM (%L) TO (%L) USING columnar', dst_part, month_start, month_end); END IF; SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position) INTO col_list FROM information_schema.columns a JOIN information_schema.columns r ON a.table_schema = r.table_schema AND a.column_name = r.column_name WHERE a.table_name = 'request_wal_archive' AND r.table_name = src_part AND a.table_schema = 'public' AND a.ordinal_position > 0; IF col_list IS NULL OR length(col_list) = 0 THEN RAISE EXCEPTION 'No common columns between % and request_wal_archive', src_part; END IF; EXECUTE format('INSERT INTO %I (%s) SELECT %s FROM %I', dst_part, col_list, col_list, src_part); GET DIAGNOSTICS row_count = ROW_COUNT; EXECUTE format('ALTER TABLE request_wal DETACH PARTITION %I', src_part); EXECUTE format('DROP TABLE %I', src_part); RETURN QUERY SELECT 'success'::text, row_count, partition_existed; END; $$;


--
