-- ============================================
-- Function: cleanup_old_credential_model_index
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

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



COMMENT ON FUNCTION public.cleanup_old_credential_model_index() IS 'Daily cleanup: removes credential_model_index rows older than 7 days from main table. Assumes historical data has been archived to credential_model_index_archive. Run daily at 3AM via background worker or cron.';



