-- ===========================================================================
-- Object:   model_probe_credential_concurrency(bigint)
-- Type:     FUNCTION
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_probe_credential_concurrency(bigint); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.model_probe_credential_concurrency(p_credential_id bigint) RETURNS integer
    LANGUAGE sql STABLE
    AS $$ SELECT COUNT(*)::INTEGER FROM model_probe_state WHERE credential_id = p_credential_id AND state = 'probing' AND probing_started_at > NOW() - INTERVAL '5 minutes'; $$;


--
