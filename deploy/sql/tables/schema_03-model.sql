-- ============================================
-- LLM Gateway Database Schema
-- Category: 03-model
-- Generated: 2026-07-05 17:14:30
-- ============================================

-- ----------------------------------------
-- Table: model_aliases
-- ----------------------------------------






-- Name: model_aliases; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_aliases (
    id bigint NOT NULL,
    canonical_id bigint NOT NULL,
    raw_name text NOT NULL,
    quantization text,
    surface text,
    status text DEFAULT 'active'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    client_profiles text[],
    CONSTRAINT model_aliases_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deprecated'::text, 'hidden'::text])))
);


-- Name: model_aliases_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.model_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: model_aliases_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.model_aliases_id_seq OWNED BY public.model_aliases.id;


-- Name: model_aliases id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_aliases ALTER COLUMN id SET DEFAULT nextval('public.model_aliases_id_seq'::regclass);


-- Name: model_aliases model_aliases_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_aliases
    ADD CONSTRAINT model_aliases_pkey PRIMARY KEY (id);


-- Name: idx_model_aliases_lower_raw_name_status; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_model_aliases_lower_raw_name_status ON public.model_aliases USING btree (lower(raw_name), status) WHERE (status = 'active'::text);



\unrestrict xeKb34FI0fvIBGVpe7p9ZwItGu1mdPUU7bfwDnkR8BdUKM3fRMvbYhVXfbtbG1H


-- ----------------------------------------
-- Table: model_credit_rates
-- ----------------------------------------






-- Name: model_credit_rates; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_credit_rates (
    canonical_id integer NOT NULL,
    credits_per_1m_in bigint,
    credits_per_1m_out bigint,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    credits_per_1m_cache_in bigint,
    credits_per_1m_cache_out bigint,
    manual_in boolean DEFAULT false NOT NULL,
    manual_out boolean DEFAULT false NOT NULL,
    manual_cache_in boolean DEFAULT false NOT NULL,
    manual_cache_out boolean DEFAULT false NOT NULL
);



\unrestrict Dk9goQxfYzmvtH6Q2DVxetAq9ELXoeDanpLpxpzIIf4MbImuFeUbRadpUiI07Qa


-- ----------------------------------------
-- Table: model_discovery_runs
-- ----------------------------------------






-- Name: model_discovery_runs; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_discovery_runs (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    trigger text DEFAULT 'manual'::text NOT NULL,
    status text DEFAULT 'running'::text NOT NULL,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone,
    heartbeat_at timestamp with time zone DEFAULT now() NOT NULL,
    lease_expires_at timestamp with time zone NOT NULL,
    requested_by text,
    request_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    summary_json jsonb,
    error text,
    CONSTRAINT chk_model_discovery_runs_status CHECK ((status = ANY (ARRAY['running'::text, 'succeeded'::text, 'failed'::text]))),
    CONSTRAINT chk_model_discovery_runs_trigger CHECK ((trigger = ANY (ARRAY['manual'::text, 'scheduled'::text, 'credential_added'::text])))
);


-- Name: model_discovery_runs_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.model_discovery_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: model_discovery_runs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.model_discovery_runs_id_seq OWNED BY public.model_discovery_runs.id;


-- Name: model_discovery_runs id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_discovery_runs ALTER COLUMN id SET DEFAULT nextval('public.model_discovery_runs_id_seq'::regclass);



\unrestrict eC1qsP4aUUgzALo7bCfUZvN8l7zEW7chPwbjY72ekfwC1muxeNyXjUYf0YsT1Rv


-- ----------------------------------------
-- Table: model_families
-- ----------------------------------------






-- Name: model_families; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_families (
    id text NOT NULL,
    display_name text NOT NULL,
    vendor text,
    status text DEFAULT 'active'::text NOT NULL,
    source text DEFAULT 'db'::text NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT model_families_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deprecated'::text, 'hidden'::text])))
);



\unrestrict fbPlRmgnKcWaZNRcrE1faDaU31EUpDS45E9C0dqanhPaRhU6xbhIYiEMjp4bsIO


-- ----------------------------------------
-- Table: model_fingerprints
-- ----------------------------------------






-- Name: model_fingerprints; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_fingerprints (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint NOT NULL,
    fingerprint_hash text NOT NULL,
    sampled_features_json jsonb,
    last_verified_at timestamp with time zone,
    drift_detected boolean DEFAULT false NOT NULL
);


-- Name: model_fingerprints_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.model_fingerprints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: model_fingerprints_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.model_fingerprints_id_seq OWNED BY public.model_fingerprints.id;


-- Name: model_fingerprints id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_fingerprints ALTER COLUMN id SET DEFAULT nextval('public.model_fingerprints_id_seq'::regclass);


-- Name: model_fingerprints model_fingerprints_credential_id_canonical_id_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_fingerprints
    ADD CONSTRAINT model_fingerprints_credential_id_canonical_id_key UNIQUE (credential_id, canonical_id);



\unrestrict FEPltZ0WCh22akJ3tkU2bs2f4TwRJJrI8JaDaHVme79E5VHdSrpznhDyiOmoUIg


-- ----------------------------------------
-- Table: model_lifecycle_jobs
-- ----------------------------------------






-- Name: model_lifecycle_jobs; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_lifecycle_jobs (
    id bigint NOT NULL,
    runtime_id bigint NOT NULL,
    action text NOT NULL,
    target text NOT NULL,
    status text DEFAULT 'queued'::text NOT NULL,
    progress_pct numeric(5,2) DEFAULT 0,
    log text,
    started_at timestamp with time zone,
    finished_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT model_lifecycle_jobs_action_check CHECK ((action = ANY (ARRAY['pull'::text, 'rm'::text, 'load'::text, 'unload'::text, 'keepalive'::text]))),
    CONSTRAINT model_lifecycle_jobs_status_check CHECK ((status = ANY (ARRAY['queued'::text, 'running'::text, 'success'::text, 'failed'::text, 'canceled'::text])))
);


-- Name: model_lifecycle_jobs_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.model_lifecycle_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: model_lifecycle_jobs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.model_lifecycle_jobs_id_seq OWNED BY public.model_lifecycle_jobs.id;


-- Name: model_lifecycle_jobs id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_lifecycle_jobs ALTER COLUMN id SET DEFAULT nextval('public.model_lifecycle_jobs_id_seq'::regclass);



\unrestrict oxLNSji6J1ytFs1ZdpeuGLem6tAHfBpX674j7hJ3Hbf7INs7OnISyApDoSDpfR5


-- ----------------------------------------
-- Table: model_offer_events
-- ----------------------------------------






-- Name: model_offer_events; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_offer_events (
    id bigint,
    ts timestamp with time zone,
    source text,
    action text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    raw_model_name text,
    reason_code text,
    reason_detail text,
    request_id text,
    run_id bigint,
    metadata_json jsonb
);



\unrestrict eeTAJ5ado7aRrIpNbHZIfnLGqT9aGTUf3rghmphbP7e4vb8emQFzQ07fhqGCfvY


-- ----------------------------------------
-- Table: model_offers_legacy
-- ----------------------------------------






-- Name: model_offers_legacy; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_offers_legacy (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    raw_model_name text NOT NULL,
    p95_latency_ms integer,
    success_rate numeric(5,4),
    available boolean DEFAULT true NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    routing_tier smallint DEFAULT 2,
    weight smallint DEFAULT 100,
    unit_price_in_per_1m numeric(12,6),
    unit_price_out_per_1m numeric(12,6),
    currency text DEFAULT 'USD'::text,
    outbound_model_name text,
    cache_read_price_per_1m numeric(12,6),
    cache_write_price_per_1m numeric(12,6),
    standardized_name text,
    unavailable_reason text,
    unavailable_at timestamp with time zone,
    billing_mode text DEFAULT 'per_token'::text,
    pricing_source text,
    pricing_updated_at timestamp with time zone,
    manual_priority smallint DEFAULT 99,
    active_sessions integer DEFAULT 0,
    consecutive_failures integer DEFAULT 0,
    CONSTRAINT model_offers_manual_priority_chk CHECK (((manual_priority >= 1) AND (manual_priority <= 99))),
    CONSTRAINT model_offers_routing_tier_chk CHECK (((routing_tier >= 1) AND (routing_tier <= 9))),
    CONSTRAINT model_offers_weight_chk CHECK (((weight >= 1) AND (weight <= 1000)))
);


-- Name: COLUMN model_offers_legacy.cache_read_price_per_1m; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_offers_legacy.cache_read_price_per_1m IS 'Per-million-token price for cache reads (NULL = use unit_price_in_per_1m)';


-- Name: COLUMN model_offers_legacy.cache_write_price_per_1m; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_offers_legacy.cache_write_price_per_1m IS 'Per-million-token price for cache writes (NULL = use unit_price_in_per_1m)';


-- Name: COLUMN model_offers_legacy.standardized_name; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_offers_legacy.standardized_name IS 'Standardized model name in format: family-version[-feature], e.g. "minimax-m2.7", "glm-4.5-flash", "claude-opus-4.8". Auto-filled on discovery, can be manually edited.';


-- Name: COLUMN model_offers_legacy.billing_mode; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_offers_legacy.billing_mode IS 'per_token | per_request | monthly | free';


-- Name: COLUMN model_offers_legacy.pricing_source; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_offers_legacy.pricing_source IS 'manual | scraped | inherited';


-- Name: model_offers_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.model_offers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: model_offers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.model_offers_id_seq OWNED BY public.model_offers_legacy.id;


-- Name: model_offers_legacy id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_offers_legacy ALTER COLUMN id SET DEFAULT nextval('public.model_offers_id_seq'::regclass);


-- Name: model_offers_legacy model_offers_credential_id_raw_model_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_offers_legacy
    ADD CONSTRAINT model_offers_credential_id_raw_model_name_key UNIQUE (credential_id, raw_model_name);



\unrestrict J8Zz8PcFaTDDEsqnpTlMsbBOg8I7tbjw4UR5mXcivnQaR6y2lZ7Q0Qarad7SDsi


-- ----------------------------------------
-- Table: model_probe_runs
-- ----------------------------------------






-- Name: model_probe_runs; Type: TABLE; Schema: public; Owner: -

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



\unrestrict lpm5S2OEszDPZsO4ZXoF94DJJNoLx4XiAhZ74WwWgbyshIa6cpzVq1JA40xA4Us


-- ----------------------------------------
-- Table: model_probe_state
-- ----------------------------------------






-- Name: model_probe_state; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_probe_state (
    credential_id bigint NOT NULL,
    raw_model_name text NOT NULL,
    state text DEFAULT 'unknown'::text NOT NULL,
    consecutive_successes integer DEFAULT 0 NOT NULL,
    consecutive_failures integer DEFAULT 0 NOT NULL,
    total_attempts integer DEFAULT 0 NOT NULL,
    last_attempt_at timestamp with time zone,
    next_retry_at timestamp with time zone DEFAULT now() NOT NULL,
    last_status text,
    last_state_change_at timestamp with time zone,
    last_state_change_run bigint,
    last_unavailable_reason text,
    last_err_code text,
    next_retry_at_override timestamp with time zone,
    state_expires_at timestamp with time zone,
    marked_suspicious_at timestamp with time zone,
    probing_started_at timestamp with time zone,
    probing_credential_concurrency integer DEFAULT 0,
    probe_priority text DEFAULT 'watchdog'::text,
    last_verified_at timestamp with time zone,
    verification_interval interval DEFAULT '04:00:00'::interval,
    success_rate_7d numeric(5,2) DEFAULT 0.00,
    consecutive_watchdog_successes integer DEFAULT 0,
    last_real_request_at timestamp with time zone,
    real_request_success_count integer DEFAULT 0,
    real_request_failure_count integer DEFAULT 0,
    verification_attempt_1_at timestamp with time zone,
    verification_attempt_2_at timestamp with time zone,
    verification_result_1 boolean,
    verification_result_2 boolean,
    verification_latency_1_ms integer,
    verification_latency_2_ms integer,
    CONSTRAINT check_probe_priority CHECK ((probe_priority = ANY (ARRAY['urgent'::text, 'suspicious'::text, 'failing'::text, 'recovering'::text, 'watchdog'::text])))
);


-- Name: TABLE model_probe_state; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.model_probe_state IS 'Per-(credential, model) probe consensus state. 3 consecutive successes to recover; 3 consecutive failures to confirm-broken.';


-- Name: COLUMN model_probe_state.consecutive_successes; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_probe_state.consecutive_successes IS 'Counter; resets to 0 on any failure. State flips to healthy_confirmed when this hits 3.';


-- Name: COLUMN model_probe_state.consecutive_failures; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_probe_state.consecutive_failures IS 'Counter; resets to 0 on any success. Stops probing when this hits 3 (broken_confirmed).';


-- Name: COLUMN model_probe_state.verification_attempt_1_at; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_probe_state.verification_attempt_1_at IS '防闪断第一次验证时间（阈值触发后约2秒）';


-- Name: COLUMN model_probe_state.verification_attempt_2_at; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_probe_state.verification_attempt_2_at IS '防闪断第二次验证时间（第一次后约3秒）';


-- Name: COLUMN model_probe_state.verification_result_1; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_probe_state.verification_result_1 IS '第一次验证结果';


-- Name: COLUMN model_probe_state.verification_result_2; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.model_probe_state.verification_result_2 IS '第二次验证结果';


-- Name: model_probe_state model_probe_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_probe_state
    ADD CONSTRAINT model_probe_state_pkey PRIMARY KEY (credential_id, raw_model_name);


-- Name: idx_model_probe_state_retry; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_model_probe_state_retry ON public.model_probe_state USING btree (state, next_retry_at) WHERE (state = 'recovering'::text);


-- Name: idx_mps_due; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_mps_due ON public.model_probe_state USING btree (next_retry_at) WHERE (state = ANY (ARRAY['unknown'::text, 'recovering'::text]));


-- Name: idx_mps_priority_next_retry; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_mps_priority_next_retry ON public.model_probe_state USING btree (probe_priority, next_retry_at) WHERE (state = ANY (ARRAY['suspicious'::text, 'failing'::text, 'recovering'::text]));


-- Name: idx_mps_probing; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_mps_probing ON public.model_probe_state USING btree (probing_started_at) WHERE (state = 'probing'::text);


-- Name: idx_mps_success_rate; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_mps_success_rate ON public.model_probe_state USING btree (success_rate_7d);


-- Name: idx_mps_suspicious_expired; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_mps_suspicious_expired ON public.model_probe_state USING btree (state_expires_at) WHERE ((state = ANY (ARRAY['available'::text, 'unavailable'::text])) AND (state_expires_at IS NOT NULL));


-- Name: idx_mps_suspicious_pending; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_mps_suspicious_pending ON public.model_probe_state USING btree (marked_suspicious_at, next_retry_at) WHERE (state = 'suspicious'::text);



\unrestrict VX23W2mAdmTzomEgA7jIxyeOll4euX3Cer7Ta9RbDN8CxHQPszyWuYTaciABjeO


-- ----------------------------------------
-- Table: model_reconcile_log
-- ----------------------------------------






-- Name: model_reconcile_log; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.model_reconcile_log (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    credential_id bigint,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    added integer DEFAULT 0 NOT NULL,
    removed integer DEFAULT 0 NOT NULL,
    changed integer DEFAULT 0 NOT NULL,
    diff_json jsonb
);


-- Name: model_reconcile_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.model_reconcile_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: model_reconcile_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.model_reconcile_log_id_seq OWNED BY public.model_reconcile_log.id;


-- Name: model_reconcile_log id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_reconcile_log ALTER COLUMN id SET DEFAULT nextval('public.model_reconcile_log_id_seq'::regclass);



\unrestrict BClizNHJBxnaRoLS2l81hgzfaEHPQ54CTCzyaxVz8UVNOEYgZV68pSLysqvuBUa


-- ----------------------------------------
-- Table: model_task_index
-- ----------------------------------------






-- Name: model_task_index; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE model_task_index; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.model_task_index IS 'Auto route: per-model-per-task 5min rolled-up performance (success/latency/cost)';


-- Name: model_task_index model_task_index_bucket_canonical_task_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.model_task_index
    ADD CONSTRAINT model_task_index_bucket_canonical_task_key UNIQUE (bucket, canonical_id, task_type);



\unrestrict va4Xv1KrgFXj3TQWRP4WVT1mEiswJWHhuZUXyUAxn6e2O80xamJpcUMNu3hh5Dm


-- ----------------------------------------
-- Table: models_canonical
-- ----------------------------------------






-- Name: models_canonical; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.models_canonical (
    id bigint NOT NULL,
    canonical_name text NOT NULL,
    family text,
    parameters_b numeric(8,2),
    modality text DEFAULT 'text'::text NOT NULL,
    context_window integer,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    tags_locked boolean DEFAULT false NOT NULL,
    tags_updated_at timestamp with time zone,
    display_name text,
    status text DEFAULT 'active'::text NOT NULL,
    source text DEFAULT 'db'::text NOT NULL,
    disabled_reason text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    input_price_cny numeric(10,4) DEFAULT 0,
    output_price_cny numeric(10,4) DEFAULT 0,
    released_at date,
    strengths text[] DEFAULT '{}'::text[] NOT NULL,
    cost_tier text DEFAULT 'unknown'::text NOT NULL,
    multimodal_caps text[] DEFAULT '{}'::text[] NOT NULL,
    version_rank integer,
    CONSTRAINT models_canonical_cost_tier_check CHECK ((cost_tier = ANY (ARRAY['free'::text, 'low'::text, 'medium'::text, 'high'::text, 'premium'::text, 'unknown'::text]))),
    CONSTRAINT models_canonical_modality_check CHECK ((modality = ANY (ARRAY['text'::text, 'vision'::text, 'audio'::text, 'multimodal'::text, 'embedding'::text]))),
    CONSTRAINT models_canonical_status_check CHECK ((status = ANY (ARRAY['active'::text, 'disabled'::text, 'deprecated'::text, 'hidden'::text])))
);


-- Name: COLUMN models_canonical.input_price_cny; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.models_canonical.input_price_cny IS 'Input price in CNY per million tokens (0 = not set/unknown)';


-- Name: COLUMN models_canonical.output_price_cny; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.models_canonical.output_price_cny IS 'Output price in CNY per million tokens (0 = not set/unknown)';


-- Name: COLUMN models_canonical.released_at; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.models_canonical.released_at IS '模型发布日期，用于 version_recency 评分维度（高难度任务偏好最新版，普通任务偏好次新版）';


-- Name: COLUMN models_canonical.strengths; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.models_canonical.strengths IS '运营标注的优势方向数组，用于 strength_match 评分维度（比 tags 更精准）';


-- Name: COLUMN models_canonical.cost_tier; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.models_canonical.cost_tier IS '成本粗评：free/low/medium/high/premium，用于快速筛选和展示';


-- Name: COLUMN models_canonical.multimodal_caps; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.models_canonical.multimodal_caps IS '多模态能力细粒度标签：vision/audio/image_gen/video/embedding 等';


-- Name: COLUMN models_canonical.version_rank; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.models_canonical.version_rank IS '版本级次：1=最新, 2=次新, 3=稳定版... 用于路由策略（普通任务偏次新，高难度偏最新）';


-- Name: models_canonical_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.models_canonical_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: models_canonical_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.models_canonical_id_seq OWNED BY public.models_canonical.id;


-- Name: models_canonical id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.models_canonical ALTER COLUMN id SET DEFAULT nextval('public.models_canonical_id_seq'::regclass);


-- Name: models_canonical models_canonical_canonical_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.models_canonical
    ADD CONSTRAINT models_canonical_canonical_name_key UNIQUE (canonical_name);


-- Name: idx_models_canonical_released; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_models_canonical_released ON public.models_canonical USING btree (released_at DESC NULLS LAST);


-- Name: idx_models_canonical_strengths; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_models_canonical_strengths ON public.models_canonical USING gin (strengths);


-- Name: idx_models_canonical_version_rank; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_models_canonical_version_rank ON public.models_canonical USING btree (version_rank);



\unrestrict G09HZOSx468NbnmDUYqeAyti6CPDgJLEiRsIb0OC9uUrZpQ97tPW5h374To6YvU


