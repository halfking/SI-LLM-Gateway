-- ===========================================================================
-- Object:   credential_model_stats_1m
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_stats_1m; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_stats_1m (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    raw_model text DEFAULT ''::text NOT NULL,
    requests integer DEFAULT 0 NOT NULL,
    successes integer DEFAULT 0 NOT NULL,
    failures integer DEFAULT 0 NOT NULL,
    latency_p50_ms integer,
    latency_p95_ms integer,
    latency_p99_ms integer,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    cost_usd numeric(14,8) DEFAULT 0 NOT NULL,
    error_counts jsonb DEFAULT '{}'::jsonb NOT NULL
);


--
