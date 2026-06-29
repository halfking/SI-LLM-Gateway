-- ===========================================================================
-- Object:   get_current_tenant()
-- Type:     FUNCTION
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: get_current_tenant(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_current_tenant() RETURNS text
    LANGUAGE sql STABLE
    AS $$ SELECT COALESCE(NULLIF(current_setting('app.current_tenant', true), ''), 'default'); $$;


--
