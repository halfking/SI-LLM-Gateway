-- ===========================================================================
-- Object:   model_probe_runs
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
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
