-- ===========================================================================
-- Object:   api_key_model_cost
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: api_key_model_cost; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.api_key_model_cost (
    bucket timestamp with time zone NOT NULL,
    api_key_id integer NOT NULL,
    canonical_id integer,
    raw_model text NOT NULL,
    billing_mode text,
    requests_total integer DEFAULT 0 NOT NULL,
    requests_success integer DEFAULT 0 NOT NULL,
    tokens_input bigint DEFAULT 0 NOT NULL,
    tokens_output bigint DEFAULT 0 NOT NULL,
    cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    active_concurrent integer DEFAULT 0 NOT NULL,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    last_request_at timestamp with time zone,
    last_decision_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now()
);


--
