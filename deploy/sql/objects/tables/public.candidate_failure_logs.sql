-- ===========================================================================
-- Object:   candidate_failure_logs
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
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
