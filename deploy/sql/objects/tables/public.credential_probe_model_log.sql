-- ===========================================================================
-- Object:   credential_probe_model_log
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
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
