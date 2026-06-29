-- ===========================================================================
-- Object:   model_task_index
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_task_index; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.model_task_index (
    bucket timestamp with time zone NOT NULL,
    canonical_id integer NOT NULL,
    task_type text NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL,
    success_rate numeric(5,4),
    avg_latency_ms integer,
    p95_latency_ms integer,
    avg_cost_per_1k_usd numeric(10,6),
    primary_credential_id bigint,
    updated_at timestamp with time zone DEFAULT now()
);


--
