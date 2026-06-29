-- ===========================================================================
-- Object:   cleanup_old_credential_model_index()
-- Type:     FUNCTION
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
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
