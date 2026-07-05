-- ============================================
-- LLM Gateway Database Schema
-- Category: 09-api-key
-- Generated: 2026-07-05 17:14:32
-- ============================================

-- ----------------------------------------
-- Table: api_key_auto_profile
-- ----------------------------------------






-- Name: api_key_auto_profile; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.api_key_auto_profile (
    api_key_id integer NOT NULL,
    profile text DEFAULT 'smart'::text NOT NULL,
    first_chosen_at timestamp with time zone DEFAULT now(),
    last_used_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT api_key_auto_profile_profile_check CHECK ((profile = ANY (ARRAY['smart'::text, 'speed_first'::text, 'cost_first'::text])))
);


-- Name: TABLE api_key_auto_profile; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.api_key_auto_profile IS 'Auto route: per-API-Key profile preference (sticky 30min)';



\unrestrict NBZ6EoGDn6oauL8jenF2uvjXGqmHg6Jpo54uIiajyMM4z2jV6gP0Dj9vuqmoP6y


-- ----------------------------------------
-- Table: api_key_model_cost
-- ----------------------------------------






-- Name: api_key_model_cost; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE api_key_model_cost; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.api_key_model_cost IS 'Auto route: per-API-Key per-model 5min rolled-up cost + concurrency + score';



\unrestrict Z3Ls9AgHNvNGblaGnUDBnilCz3WKWzG66Y1TQ1bZpUo19WKunQbHxSiqSzz2HVQ


-- ----------------------------------------
-- Table: api_keys
-- ----------------------------------------






-- Name: api_keys; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.api_keys (
    id bigint NOT NULL,
    application_id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    key_hash text NOT NULL,
    key_prefix text NOT NULL,
    owner_user text,
    data_sensitivity text DEFAULT 'internal'::text NOT NULL,
    default_end_user_id text,
    budget_usd numeric(14,6),
    rate_limit_rpm integer,
    enabled boolean DEFAULT true NOT NULL,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    last_used_at timestamp with time zone,
    status character varying(16) DEFAULT 'active'::character varying NOT NULL,
    key_ciphertext text,
    is_system boolean DEFAULT false NOT NULL,
    rate_limit_concurrent integer,
    rate_limit_tpm integer,
    key_tier character varying(16) DEFAULT 'default'::character varying NOT NULL,
    key_ciphertext_kid text,
    throttled_at timestamp with time zone,
    throttled_reason text,
    ewma_rpm_baseline numeric(10,3),
    ewma_updated_at timestamp with time zone,
    reveal_count integer DEFAULT 0 NOT NULL,
    last_revealed_at timestamp with time zone,
    last_revealed_by text,
    remark text,
    key_alias text,
    total_requests bigint DEFAULT 0 NOT NULL,
    total_prompt_tokens bigint DEFAULT 0 NOT NULL,
    total_completion_tokens bigint DEFAULT 0 NOT NULL,
    total_tokens bigint DEFAULT 0 NOT NULL,
    total_cost_usd numeric(14,8) DEFAULT 0 NOT NULL,
    last_request_at timestamp with time zone,
    default_client_profile text,
    CONSTRAINT api_keys_data_sensitivity_check CHECK ((data_sensitivity = ANY (ARRAY['public'::text, 'internal'::text, 'confidential'::text]))),
    CONSTRAINT api_keys_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('pending'::character varying)::text, ('disabled'::character varying)::text, ('throttled'::character varying)::text, ('revoked'::character varying)::text])))
);


-- Name: COLUMN api_keys.status; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.status IS 'active | pending | disabled | throttled (auto-frozen) | revoked (permanent ban)';


-- Name: COLUMN api_keys.is_system; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.is_system IS 'System key - should not be disabled (e.g., admin login key)';


-- Name: COLUMN api_keys.rate_limit_concurrent; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.rate_limit_concurrent IS 'Per-key concurrent request cap (NULL = use tier default)';


-- Name: COLUMN api_keys.rate_limit_tpm; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.rate_limit_tpm IS 'Tokens per minute cap (NULL = no limit)';


-- Name: COLUMN api_keys.key_tier; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.key_tier IS 'system | production | default | applicant';


-- Name: COLUMN api_keys.key_ciphertext_kid; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.key_ciphertext_kid IS 'kid that was used when key_ciphertext was last written (v1 AES-GCM envelope)';


-- Name: COLUMN api_keys.throttled_at; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.throttled_at IS 'Timestamp when the key was auto-throttled by anomaly detection';


-- Name: COLUMN api_keys.ewma_rpm_baseline; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.ewma_rpm_baseline IS 'Rolling EWMA baseline RPM for anomaly detection (7-day window)';


-- Name: COLUMN api_keys.remark; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.remark IS 'Reason for key creation (system-created keys must explain why)';


-- Name: COLUMN api_keys.key_alias; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.key_alias IS 'Optional human-readable alias for the key';


-- Name: COLUMN api_keys.total_requests; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.total_requests IS 'Cumulative count of requests authenticated by this key';


-- Name: COLUMN api_keys.total_prompt_tokens; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.total_prompt_tokens IS 'Cumulative prompt token count';


-- Name: COLUMN api_keys.total_completion_tokens; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.total_completion_tokens IS 'Cumulative completion token count';


-- Name: COLUMN api_keys.total_cost_usd; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.total_cost_usd IS 'Cumulative cost in USD';


-- Name: COLUMN api_keys.last_request_at; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.api_keys.last_request_at IS 'When this key last made a request (denormalized from usage_ledger)';


-- Name: api_keys_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.api_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: api_keys_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.api_keys_id_seq OWNED BY public.api_keys.id;


-- Name: api_keys id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.api_keys ALTER COLUMN id SET DEFAULT nextval('public.api_keys_id_seq'::regclass);


-- Name: api_keys api_keys_key_hash_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_key_hash_key UNIQUE (key_hash);


-- Name: api_keys api_keys_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);


-- Name: api_keys trg_notify_auto_route_apikeys; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_notify_auto_route_apikeys AFTER UPDATE OF rate_limit_rpm, budget_usd, enabled, status ON public.api_keys FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();



\unrestrict II7dpGTHhXNv0s9oKqtD2GjSCIztd8tMNBwaPz3inhUCRnRlVcrkmwOfR0afKQl


