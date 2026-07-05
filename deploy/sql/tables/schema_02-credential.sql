-- ============================================
-- LLM Gateway Database Schema
-- Category: 02-credential
-- Generated: 2026-07-05 17:14:28
-- ============================================

-- ----------------------------------------
-- Table: credential_capabilities
-- ----------------------------------------






-- Name: credential_capabilities; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_capabilities (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    capability text NOT NULL,
    supported boolean DEFAULT false NOT NULL,
    last_tested_at timestamp with time zone,
    evidence_json jsonb,
    CONSTRAINT credential_capabilities_capability_check CHECK ((capability = ANY (ARRAY['tool_use'::text, 'vision'::text, 'streaming'::text, 'prompt_caching'::text, 'structured_output'::text, 'long_context'::text, 'json_mode'::text, 'batch'::text])))
);


-- Name: credential_capabilities_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credential_capabilities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credential_capabilities_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credential_capabilities_id_seq OWNED BY public.credential_capabilities.id;


-- Name: credential_capabilities id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_capabilities ALTER COLUMN id SET DEFAULT nextval('public.credential_capabilities_id_seq'::regclass);


-- Name: credential_capabilities credential_capabilities_credential_id_capability_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_capabilities
    ADD CONSTRAINT credential_capabilities_credential_id_capability_key UNIQUE (credential_id, capability);



\unrestrict B2I1mFBBYQ9A6ApwmcUXUfvJGH8u9q6sCgD4bO2iG2Sx7nazMTR2DTRvgjo5MQD


-- ----------------------------------------
-- Table: credential_health_checks
-- ----------------------------------------






-- Name: credential_health_checks; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_health_checks (
    id bigint NOT NULL,
    run_id bigint,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    provider_id bigint NOT NULL,
    credential_id bigint NOT NULL,
    models_ok boolean DEFAULT false NOT NULL,
    probe_ok boolean DEFAULT false NOT NULL,
    health_status text NOT NULL,
    warning_code text,
    classification_reason text,
    models_failure_reason text,
    models_http_status integer,
    probe_http_status integer,
    models_latency_ms integer,
    probe_latency_ms integer,
    probe_model text,
    models_error text,
    probe_error text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_credential_health_checks_models_failure_reason CHECK (((models_failure_reason IS NULL) OR (models_failure_reason = ANY (ARRAY['request_failed'::text, 'empty_models'::text, 'invalid_payload'::text, 'not_supported'::text])))),
    CONSTRAINT chk_credential_health_checks_status CHECK ((health_status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'warning'::text, 'unreachable'::text])))
);


-- Name: credential_health_checks_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credential_health_checks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credential_health_checks_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credential_health_checks_id_seq OWNED BY public.credential_health_checks.id;


-- Name: credential_health_checks id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_health_checks ALTER COLUMN id SET DEFAULT nextval('public.credential_health_checks_id_seq'::regclass);



\unrestrict JoHodCtFDveZqGokt4utls28Oe0gxLH3wCQQEevWgJ5PCNjEcXq9L5M1dwzgoxK


-- ----------------------------------------
-- Table: credential_model_bindings
-- ----------------------------------------






-- Name: credential_model_bindings; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_bindings (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    provider_model_id bigint NOT NULL,
    routing_tier smallint DEFAULT 2,
    weight smallint DEFAULT 100,
    manual_priority smallint DEFAULT 99,
    success_rate numeric,
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    consecutive_failures integer DEFAULT 0,
    unit_price_in_per_1m numeric,
    unit_price_out_per_1m numeric,
    cache_read_price_per_1m numeric,
    cache_write_price_per_1m numeric,
    currency text DEFAULT 'USD'::text,
    billing_mode text DEFAULT 'per_token'::text,
    pricing_source text,
    pricing_updated_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    available boolean DEFAULT true NOT NULL,
    unavailable_reason text,
    unavailable_at timestamp with time zone,
    plan_meta jsonb DEFAULT '{}'::jsonb NOT NULL,
    admin_protected boolean DEFAULT false NOT NULL,
    unavailable_recover_at timestamp with time zone,
    transient_failure_count integer DEFAULT 0,
    pending_verification boolean DEFAULT false,
    plan_type_origin text DEFAULT 'auto'::text,
    CONSTRAINT credential_model_bindings_plan_type_origin_check CHECK ((plan_type_origin = ANY (ARRAY['auto'::text, 'manual'::text, 'backfill'::text])))
);


-- Name: TABLE credential_model_bindings; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.credential_model_bindings IS 'Many-to-many: which credential can access which model, with routing/pricing attrs';


-- Name: COLUMN credential_model_bindings.billing_mode; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_bindings.billing_mode IS 'Billing mode: token (PAYG per-1M) | token_plan (prepaid credits/package) | code_plan (subscription, monthly fee + bundle) | free (rate=0) | per_token/per_request/monthly (legacy aliases)';


-- Name: COLUMN credential_model_bindings.plan_meta; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_bindings.plan_meta IS 'Subscription/plan metadata: {monthly_cny, included_tokens, tier, validity_days, modality, etc.}. Mirrors pricing_plans.plan_json at offer level.';


-- Name: COLUMN credential_model_bindings.transient_failure_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_bindings.transient_failure_count IS '触发验证时的失败计数快照（非实时；实时计数在 Redis 滑动窗口）';


-- Name: COLUMN credential_model_bindings.pending_verification; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_bindings.pending_verification IS '是否有进行中的双重验证';


-- Name: credential_model_bindings_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credential_model_bindings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credential_model_bindings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credential_model_bindings_id_seq OWNED BY public.credential_model_bindings.id;


-- Name: credential_model_bindings id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_bindings ALTER COLUMN id SET DEFAULT nextval('public.credential_model_bindings_id_seq'::regclass);


-- Name: credential_model_bindings cmb_unique_credential_model; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_bindings
    ADD CONSTRAINT cmb_unique_credential_model UNIQUE (credential_id, provider_model_id);


-- Name: idx_cmb_credential_provider_model; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_cmb_credential_provider_model ON public.credential_model_bindings USING btree (credential_id, provider_model_id);


-- Name: idx_cmb_pending_verification; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_cmb_pending_verification ON public.credential_model_bindings USING btree (credential_id) WHERE (pending_verification = true);


-- Name: idx_cmb_unavailable_recover_at; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_cmb_unavailable_recover_at ON public.credential_model_bindings USING btree (unavailable_recover_at) WHERE (available = false);


-- Name: credential_model_bindings cmb_protect_manual_disable; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER cmb_protect_manual_disable BEFORE UPDATE ON public.credential_model_bindings FOR EACH ROW EXECUTE FUNCTION public.trg_cmb_protect_manual_disable();


-- Name: credential_model_bindings trg_notify_auto_route_cmb; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_notify_auto_route_cmb AFTER INSERT OR DELETE OR UPDATE ON public.credential_model_bindings FOR EACH ROW EXECUTE FUNCTION public.notify_auto_route_refresh();



\unrestrict EHTytzxvnia71MrOfwhgldCF0D0PTjmFNwJ5Icn8TiLE18ZfN0eoBBudLgYe7YO


-- ----------------------------------------
-- Table: credential_model_call_history
-- ----------------------------------------






-- Name: credential_model_call_history; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_call_history (
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    window_start timestamp with time zone NOT NULL,
    total_calls integer DEFAULT 0 NOT NULL,
    success_calls integer DEFAULT 0 NOT NULL,
    failed_calls integer DEFAULT 0 NOT NULL,
    avg_latency_ms numeric(8,2),
    p95_latency_ms integer,
    p99_latency_ms integer,
    error_rate_limit_count integer DEFAULT 0 NOT NULL,
    error_quota_count integer DEFAULT 0 NOT NULL,
    error_concurrent_count integer DEFAULT 0 NOT NULL,
    error_network_count integer DEFAULT 0 NOT NULL,
    error_auth_count integer DEFAULT 0 NOT NULL,
    error_other_count integer DEFAULT 0 NOT NULL,
    avg_concurrent numeric(5,2),
    peak_concurrent integer,
    created_at timestamp with time zone DEFAULT now()
);


-- Name: TABLE credential_model_call_history; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.credential_model_call_history IS 'Aggregated call history per (credential, model) in 1-minute windows. Used for intelligent availability tracking, continuous failure detection, and concurrency auto-tuning.';


-- Name: COLUMN credential_model_call_history.error_rate_limit_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_call_history.error_rate_limit_count IS '429 rate limit errors - triggers concurrency reduction';


-- Name: COLUMN credential_model_call_history.error_concurrent_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_call_history.error_concurrent_count IS '503 concurrent overload errors - triggers concurrency reduction';


-- Name: COLUMN credential_model_call_history.avg_concurrent; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_call_history.avg_concurrent IS 'Average concurrent requests in this window - used for auto-scaleup';


-- Name: COLUMN credential_model_call_history.peak_concurrent; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credential_model_call_history.peak_concurrent IS 'Peak concurrent requests in this window - used for capacity planning';


-- Name: credential_model_call_history credential_model_call_history_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_call_history
    ADD CONSTRAINT credential_model_call_history_pkey PRIMARY KEY (credential_id, raw_model, window_start);


-- Name: idx_call_history_cred_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_call_history_cred_time ON public.credential_model_call_history USING btree (credential_id, window_start DESC);


-- Name: idx_call_history_errors; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_call_history_errors ON public.credential_model_call_history USING btree (credential_id, raw_model, window_start DESC) WHERE ((error_rate_limit_count > 0) OR (error_concurrent_count > 0));


-- Name: idx_call_history_model_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_call_history_model_time ON public.credential_model_call_history USING btree (raw_model, window_start DESC);



\unrestrict DdgtV07rcIkJ7hFrmfJgN9NFKhXKqpRQifNT46aXCYjrPt3jyyhh7s7j3Al81Dl


-- ----------------------------------------
-- Table: credential_model_index
-- ----------------------------------------





-- Name: credential_model_index; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_index (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
)
PARTITION BY RANGE (bucket);


-- Name: TABLE credential_model_index; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.credential_model_index IS '5-min rollup of per-credential health metrics. Monthly partitions (heap). Data older than 7 days is archived to credential_model_index_archive (columnar) by archive_credential_model_index() — see migration 317.';


-- Name: credential_model_index_bucket_cred_model_key; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX credential_model_index_bucket_cred_model_key ON ONLY public.credential_model_index USING btree (bucket, credential_id, raw_model);



\unrestrict Vb2zAA0jrwwNttr3QjENEexraG8B6tOt3Xn0E6BuFwEPstXjaj9eGko7CRA9irA


-- ----------------------------------------
-- Table: credential_model_index_2026_06
-- ----------------------------------------






-- Name: credential_model_index_2026_06; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_index_2026_06 (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
);


-- Name: credential_model_index_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


-- Name: credential_model_index_2026_0_bucket_credential_id_raw_mod_idx3; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX credential_model_index_2026_0_bucket_credential_id_raw_mod_idx3 ON public.credential_model_index_2026_06 USING btree (bucket, credential_id, raw_model);


-- Name: credential_model_index_2026_0_bucket_credential_id_raw_mod_idx3; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_2026_0_bucket_credential_id_raw_mod_idx3;



\unrestrict IfQme6EcVURWDypgQgbeu2jMY8boA4dBHa18KMZh5ek2RFTglkcQCkCarTAKZdg


-- ----------------------------------------
-- Table: credential_model_index_2026_07
-- ----------------------------------------






-- Name: credential_model_index_2026_07; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_index_2026_07 (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
);


-- Name: credential_model_index_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


-- Name: credential_model_index_2026_0_bucket_credential_id_raw_mode_idx; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX credential_model_index_2026_0_bucket_credential_id_raw_mode_idx ON public.credential_model_index_2026_07 USING btree (bucket, credential_id, raw_model);


-- Name: credential_model_index_2026_0_bucket_credential_id_raw_mode_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_2026_0_bucket_credential_id_raw_mode_idx;



\unrestrict WLsgqekpsTM1MMOA6VU0p1qApxuJ3eDc0t5SvDF8tOUvt9EJE5LxYxzhKDfEnfM


-- ----------------------------------------
-- Table: credential_model_index_2026_08
-- ----------------------------------------






-- Name: credential_model_index_2026_08; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_index_2026_08 (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
);


-- Name: credential_model_index_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


-- Name: credential_model_index_2026_0_bucket_credential_id_raw_mod_idx1; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX credential_model_index_2026_0_bucket_credential_id_raw_mod_idx1 ON public.credential_model_index_2026_08 USING btree (bucket, credential_id, raw_model);


-- Name: credential_model_index_2026_0_bucket_credential_id_raw_mod_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_2026_0_bucket_credential_id_raw_mod_idx1;



\unrestrict BtDcJVpvcctuKKYK11dFVYc9pSpuHVTcfEad7Cskrf92FcfZ8jIqmp7aq7NwpuT


-- ----------------------------------------
-- Table: credential_model_index_archive
-- ----------------------------------------





-- Name: credential_model_index_archive; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_index_archive (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
)
PARTITION BY RANGE (bucket);


-- Name: idx_cmi_archive_bucket; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_cmi_archive_bucket ON ONLY public.credential_model_index_archive USING btree (bucket DESC);


-- Name: idx_cmi_archive_canonical; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_cmi_archive_canonical ON ONLY public.credential_model_index_archive USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);


-- Name: idx_cmi_archive_cred_model; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_cmi_archive_cred_model ON ONLY public.credential_model_index_archive USING btree (credential_id, raw_model, bucket DESC);



\unrestrict 1pTZZ8hSUajnwkdvkcWi9vZG1EwEcfQRqJByqAvmeAnf9YYIUvRNkNO6oleDPLc


-- ----------------------------------------
-- Table: credential_model_index_archive_2026_08
-- ----------------------------------------






-- Name: credential_model_index_archive_2026_08; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_index_archive_2026_08 (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
);


-- Name: credential_model_index_archive_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_index_archive ATTACH PARTITION public.credential_model_index_archive_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


-- Name: credential_model_index_archiv_credential_id_raw_model_bucke_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credential_model_index_archiv_credential_id_raw_model_bucke_idx ON public.credential_model_index_archive_2026_08 USING btree (credential_id, raw_model, bucket DESC);


-- Name: credential_model_index_archive_2026_08_bucket_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credential_model_index_archive_2026_08_bucket_idx ON public.credential_model_index_archive_2026_08 USING btree (bucket DESC);


-- Name: credential_model_index_archive_2026_08_canonical_id_bucket_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX credential_model_index_archive_2026_08_canonical_id_bucket_idx ON public.credential_model_index_archive_2026_08 USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);


-- Name: credential_model_index_archiv_credential_id_raw_model_bucke_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_cmi_archive_cred_model ATTACH PARTITION public.credential_model_index_archiv_credential_id_raw_model_bucke_idx;


-- Name: credential_model_index_archive_2026_08_bucket_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_cmi_archive_bucket ATTACH PARTITION public.credential_model_index_archive_2026_08_bucket_idx;


-- Name: credential_model_index_archive_2026_08_canonical_id_bucket_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_cmi_archive_canonical ATTACH PARTITION public.credential_model_index_archive_2026_08_canonical_id_bucket_idx;



\unrestrict h5sUZTGUjjVxurpJeaeAEZGURGDeABgv8PfHfkYErC170eyscvxM3QdZc2NWeh3


-- ----------------------------------------
-- Table: credential_model_index_default
-- ----------------------------------------






-- Name: credential_model_index_default; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_index_default (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text NOT NULL,
    canonical_id integer,
    billing_mode text,
    unit_price_in_per_1m numeric(10,4),
    unit_price_out_per_1m numeric(10,4),
    context_window integer,
    success_rate numeric(5,4),
    p95_latency_ms integer,
    active_sessions integer DEFAULT 0,
    concurrency_limit integer,
    pressure_ratio numeric(5,4),
    score_smart numeric(8,4),
    score_speed_first numeric(8,4),
    score_cost_first numeric(8,4),
    updated_at timestamp with time zone DEFAULT now()
);


-- Name: credential_model_index_default; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_default DEFAULT;


-- Name: credential_model_index_defaul_bucket_credential_id_raw_mode_idx; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX credential_model_index_defaul_bucket_credential_id_raw_mode_idx ON public.credential_model_index_default USING btree (bucket, credential_id, raw_model);


-- Name: credential_model_index_defaul_bucket_credential_id_raw_mode_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_defaul_bucket_credential_id_raw_mode_idx;



\unrestrict aJFtFnQevoEikgQzaJ9FidJb19MBazDq8jvSeZCBzH2d37VjJopFDkiTwxbK35O


-- ----------------------------------------
-- Table: credential_model_peak_1m
-- ----------------------------------------






-- Name: credential_model_peak_1m; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_peak_1m (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    peak_concurrent integer DEFAULT 0 NOT NULL,
    avg_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL
);


-- Name: TABLE credential_model_peak_1m; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.credential_model_peak_1m IS 'Per-minute peak concurrency per credential-model pair (used by auto-tune)';



\unrestrict b8DrqUfrGYNg91NeEJEIAFUxaLzMXHqVEI1bMMxZm87QXh8VSbuh230SYosPgBa


-- ----------------------------------------
-- Table: credential_model_stats_1m
-- ----------------------------------------






-- Name: credential_model_stats_1m; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE credential_model_stats_1m; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.credential_model_stats_1m IS 'Per-minute aggregated routing stats, used for sliding window queries';



\unrestrict QjZCJ1G4eYFh4JPtfLWyS59ThllGXzat0UnY3VT0iJ0koSHDNtLEVVZSdJKmCTY


-- ----------------------------------------
-- Table: credential_model_weekly_peak
-- ----------------------------------------






-- Name: credential_model_weekly_peak; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_model_weekly_peak (
    week_start timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    peak_concurrent integer DEFAULT 0 NOT NULL,
    peak_concurrent_5min integer DEFAULT 0 NOT NULL,
    p95_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    avg_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    total_requests bigint DEFAULT 0 NOT NULL,
    sample_days integer DEFAULT 0 NOT NULL,
    current_limit integer DEFAULT 0 NOT NULL,
    suggested_limit integer,
    suggestion_reason text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


-- Name: TABLE credential_model_weekly_peak; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.credential_model_weekly_peak IS 'Weekly aggregated peak concurrency for auto-tune suggestions';



\unrestrict R2FL32oA0mJswzZ1NY3fLynnkXTF7ufOwmNaLNhI3hmNcTdo5mU1VIoKOHyZdqo


-- ----------------------------------------
-- Table: credential_probe_configs
-- ----------------------------------------






-- Name: credential_probe_configs; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_probe_configs (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    probe_model text NOT NULL,
    priority integer DEFAULT 1,
    enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);


-- Name: credential_probe_configs_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credential_probe_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credential_probe_configs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credential_probe_configs_id_seq OWNED BY public.credential_probe_configs.id;


-- Name: credential_probe_configs id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_probe_configs ALTER COLUMN id SET DEFAULT nextval('public.credential_probe_configs_id_seq'::regclass);


-- Name: credential_probe_configs credential_probe_configs_credential_id_probe_model_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_probe_configs
    ADD CONSTRAINT credential_probe_configs_credential_id_probe_model_key UNIQUE (credential_id, probe_model);


-- Name: credential_probe_configs credential_probe_configs_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_probe_configs
    ADD CONSTRAINT credential_probe_configs_pkey PRIMARY KEY (id);


-- Name: credential_probe_configs credential_probe_configs_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_probe_configs
    ADD CONSTRAINT credential_probe_configs_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.credentials(id);



\unrestrict KhggJNgIOcrjFwojyRAKHeYokOFYDgxmhCeuz5Q7q9m1W0IOQXTjiXCUix1jRFd


-- ----------------------------------------
-- Table: credential_probe_model_log
-- ----------------------------------------






-- Name: credential_probe_model_log; Type: TABLE; Schema: public; Owner: -

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



\unrestrict 1FGX0GGOFkgRx6mH179LuhYJZT8obPBHwgP9C1ABErqB9PNkR1f1paSw5dmoxk5


-- ----------------------------------------
-- Table: credential_probes
-- ----------------------------------------






-- Name: credential_probes; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_probes (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    provider_id bigint NOT NULL,
    probe_model text NOT NULL,
    success boolean NOT NULL,
    http_status integer,
    latency_ms integer,
    error_kind text,
    error_message text,
    response_preview text,
    triggered_by text DEFAULT 'scheduled'::text,
    created_at timestamp with time zone DEFAULT now()
);


-- Name: credential_probes_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credential_probes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credential_probes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credential_probes_id_seq OWNED BY public.credential_probes.id;


-- Name: credential_probes id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_probes ALTER COLUMN id SET DEFAULT nextval('public.credential_probes_id_seq'::regclass);


-- Name: credential_probes credential_probes_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_probes
    ADD CONSTRAINT credential_probes_pkey PRIMARY KEY (id);


-- Name: idx_credential_probes_cred_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_credential_probes_cred_time ON public.credential_probes USING btree (credential_id, created_at DESC);


-- Name: idx_credential_probes_success; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_credential_probes_success ON public.credential_probes USING btree (success, created_at DESC);


-- Name: credential_probes credential_probes_credential_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_probes
    ADD CONSTRAINT credential_probes_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.credentials(id);



\unrestrict yYj7TOWbkmluUhTCASPLyDUr8dxccDzePmrQgnp4duEZaqGsQ2nmyOsiF56vtWj


-- ----------------------------------------
-- Table: credential_quota_usage
-- ----------------------------------------






-- Name: credential_quota_usage; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_quota_usage (
    id bigint NOT NULL,
    quota_id bigint NOT NULL,
    window_started_at timestamp with time zone NOT NULL,
    window_ends_at timestamp with time zone NOT NULL,
    used_total_tokens bigint DEFAULT 0 NOT NULL,
    used_input_tokens bigint DEFAULT 0 NOT NULL,
    used_output_tokens bigint DEFAULT 0 NOT NULL,
    used_requests bigint DEFAULT 0 NOT NULL,
    used_cost_usd numeric(18,8) DEFAULT 0 NOT NULL,
    last_event_at timestamp with time zone,
    exhausted boolean DEFAULT false NOT NULL
);


-- Name: credential_quota_usage_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credential_quota_usage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credential_quota_usage_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credential_quota_usage_id_seq OWNED BY public.credential_quota_usage.id;


-- Name: credential_quota_usage id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_quota_usage ALTER COLUMN id SET DEFAULT nextval('public.credential_quota_usage_id_seq'::regclass);


-- Name: credential_quota_usage credential_quota_usage_quota_id_window_started_at_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_quota_usage
    ADD CONSTRAINT credential_quota_usage_quota_id_window_started_at_key UNIQUE (quota_id, window_started_at);



\unrestrict wNLOiC1kRRQEwItwZQMDezvUeTcn42ilmNl99hdtvB77xfDD31nghR4GGg5fpDh


-- ----------------------------------------
-- Table: credential_quotas
-- ----------------------------------------






-- Name: credential_quotas; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credential_quotas (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    quota_name text NOT NULL,
    window_type text NOT NULL,
    starts_at timestamp with time zone,
    ends_at timestamp with time zone,
    period text,
    cron_expr text,
    timezone text DEFAULT 'UTC'::text NOT NULL,
    reset_anchor_local time without time zone,
    rolling_seconds integer,
    cap_total_tokens bigint,
    cap_input_tokens bigint,
    cap_output_tokens bigint,
    cap_requests bigint,
    cap_cost_usd numeric(14,6),
    unlimited_in_window boolean DEFAULT false NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    priority integer DEFAULT 100 NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT credential_quotas_window_type_check CHECK ((window_type = ANY (ARRAY['fixed'::text, 'recurring'::text, 'rolling'::text])))
);


-- Name: credential_quotas_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credential_quotas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credential_quotas_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credential_quotas_id_seq OWNED BY public.credential_quotas.id;


-- Name: credential_quotas id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_quotas ALTER COLUMN id SET DEFAULT nextval('public.credential_quotas_id_seq'::regclass);


-- Name: credential_quotas credential_quotas_credential_id_quota_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credential_quotas
    ADD CONSTRAINT credential_quotas_credential_id_quota_name_key UNIQUE (credential_id, quota_name);



\unrestrict eYbAiPJf8qXsNkR9NYUQ5DGjYQkn41hRQMf6QDqvq7fzl5dQqS88TXSavfEPr7A


-- ----------------------------------------
-- Table: credentials
-- ----------------------------------------






-- Name: credentials; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.credentials (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    label text NOT NULL,
    secret_ciphertext bytea,
    secret_kid text,
    trust_level text DEFAULT 'trusted'::text NOT NULL,
    status text DEFAULT 'active'::text NOT NULL,
    concurrency_limit integer,
    effective_concurrency integer,
    balance_usd numeric(14,6),
    pricing_distrust boolean DEFAULT false NOT NULL,
    relay_overhead_ms integer,
    active_plan_id bigint,
    plan_consumed_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    api_models_ok boolean,
    api_models_last_checked_at timestamp with time zone,
    api_models_error text,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    circuit_state text DEFAULT 'closed'::text,
    circuit_opened_at timestamp with time zone,
    consecutive_failures integer DEFAULT 0,
    cooling_until timestamp with time zone,
    circuit_open_count_window integer DEFAULT 0,
    circuit_window_started_at timestamp with time zone,
    effective_at timestamp with time zone,
    expires_at timestamp with time zone,
    tags jsonb DEFAULT '[]'::jsonb,
    notes text,
    health_status text DEFAULT 'unknown'::text NOT NULL,
    health_checked_at timestamp with time zone,
    health_source text,
    health_warning_code text,
    health_error text,
    health_latency_ms integer,
    health_probe_model text,
    lifecycle_status text DEFAULT 'active'::text NOT NULL,
    availability_state text DEFAULT 'ready'::text NOT NULL,
    quota_state text DEFAULT 'ok'::text NOT NULL,
    state_reason_code text,
    state_reason_detail text,
    state_updated_at timestamp with time zone,
    availability_recover_at timestamp with time zone,
    quota_recover_at timestamp with time zone,
    balance_currency text DEFAULT 'USD'::text,
    balance_last_checked_at timestamp with time zone,
    balance_check_endpoint text,
    pool_group text,
    acquisition_source text,
    acquisition_detail text,
    manual_disabled boolean DEFAULT false NOT NULL,
    default_probe_model text,
    default_probe_model_source text,
    default_probe_model_picked_at timestamp with time zone,
    concurrency_limit_auto integer,
    fp_slot_limit integer NOT NULL,
    probe_enabled boolean DEFAULT true,
    probe_interval_sec integer DEFAULT 300,
    last_probe_at timestamp with time zone,
    last_probe_success boolean,
    probe_consecutive_failures integer DEFAULT 0,
    probe_failure_threshold integer DEFAULT 3,
    plan_type text DEFAULT 'token'::text,
    CONSTRAINT chk_credentials_health_source CHECK (((health_source IS NULL) OR (health_source = ANY (ARRAY['models'::text, 'probe'::text, 'mixed'::text, 'none'::text, 'fast_reprobe'::text])))),
    CONSTRAINT chk_credentials_health_status CHECK ((health_status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'warning'::text, 'unreachable'::text]))),
    CONSTRAINT credentials_availability_state_check CHECK ((availability_state = ANY (ARRAY['ready'::text, 'cooling'::text, 'rate_limited'::text, 'auth_failed'::text, 'unreachable'::text, 'suspended'::text]))),
    CONSTRAINT credentials_circuit_state_chk CHECK ((circuit_state = ANY (ARRAY['closed'::text, 'open'::text, 'half_open'::text]))),
    CONSTRAINT credentials_fp_slot_limit_check CHECK (((fp_slot_limit >= 0) AND (fp_slot_limit <= 10000))),
    CONSTRAINT credentials_fp_slot_vs_concurrency CHECK (((concurrency_limit IS NULL) OR (fp_slot_limit IS NULL) OR (fp_slot_limit <= concurrency_limit))),
    CONSTRAINT credentials_lifecycle_status_check CHECK ((lifecycle_status = ANY (ARRAY['active'::text, 'disabled'::text, 'suspended'::text, 'retired'::text]))),
    CONSTRAINT credentials_plan_type_check CHECK ((plan_type = ANY (ARRAY['token'::text, 'token_plan'::text, 'code_plan'::text, 'agent_plan'::text, 'monthly'::text, 'free'::text]))),
    CONSTRAINT credentials_status_check CHECK ((status = ANY (ARRAY['active'::text, 'cooling'::text, 'degraded'::text, 'quarantine'::text, 'quota_expired'::text, 'disabled'::text]))),
    CONSTRAINT credentials_trust_level_check CHECK ((trust_level = ANY (ARRAY['trusted'::text, 'cooling'::text, 'degraded'::text, 'quarantine'::text])))
);


-- Name: COLUMN credentials.api_models_ok; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.api_models_ok IS '最近一次模型清单 API 拉取是否成功（NULL=未验证）';


-- Name: COLUMN credentials.api_models_last_checked_at; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.api_models_last_checked_at IS '最近一次模型清单 API 验证时间';


-- Name: COLUMN credentials.api_models_error; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.api_models_error IS '最近一次模型清单 API 验证失败原因（HTTP 状态码 + 错误摘要，已脱敏）';


-- Name: COLUMN credentials.balance_check_endpoint; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.balance_check_endpoint IS 'URL template to check remaining balance';


-- Name: COLUMN credentials.pool_group; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.pool_group IS 'free | shared | dedicated | NULL';


-- Name: COLUMN credentials.acquisition_source; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.acquisition_source IS 'Free pool: signup | env | oauth | mirrored | discovered | no_key | manual';


-- Name: COLUMN credentials.acquisition_detail; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.acquisition_detail IS 'Free pool source detail: env var name, mirror source label, oauth file, signup URL, etc.';


-- Name: COLUMN credentials.concurrency_limit_auto; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.concurrency_limit_auto IS 'Algorithm-recommended concurrency limit. Adjusted dynamically based on 429/503 errors and success rate. Read priority: concurrency_limit (manual) > concurrency_limit_auto > default 5.';


-- Name: COLUMN credentials.fp_slot_limit; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.credentials.fp_slot_limit IS 'Fingerprint slot pool size: number of distinct virtual user identities this credential can simulate. 0 = unlimited. Distinct from concurrency_limit which controls in-flight request count.';


-- Name: CONSTRAINT credentials_fp_slot_vs_concurrency ON credentials; Type: COMMENT; Schema: public; Owner: -

COMMENT ON CONSTRAINT credentials_fp_slot_vs_concurrency ON public.credentials IS 'fp_slot_limit (distinct user identities) MUST be <= concurrency_limit (in-flight requests). Otherwise the fingerprint pool exceeds the upstream capacity, defeating anti-rate-limit.';


-- Name: credentials_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: credentials_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.credentials_id_seq OWNED BY public.credentials.id;


-- Name: credentials id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.credentials ALTER COLUMN id SET DEFAULT nextval('public.credentials_id_seq'::regclass);


-- Name: credentials credentials_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (id);


-- Name: credentials credentials_unique_provider_label; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_unique_provider_label UNIQUE (provider_id, tenant_id, label);


-- Name: idx_credentials_auto_limit; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_credentials_auto_limit ON public.credentials USING btree (concurrency_limit_auto) WHERE (concurrency_limit_auto IS NOT NULL);


-- Name: credentials trg_auto_fp_slot_limit_insert; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_auto_fp_slot_limit_insert BEFORE INSERT ON public.credentials FOR EACH ROW EXECUTE FUNCTION public.auto_set_fp_slot_limit();


-- Name: credentials trg_check_credential_dates; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_check_credential_dates BEFORE INSERT OR UPDATE ON public.credentials FOR EACH ROW EXECUTE FUNCTION public.check_credential_dates();


-- Name: credentials trg_notify_auto_route_creds; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_notify_auto_route_creds AFTER UPDATE OF status, availability_state, quota_state, circuit_state, concurrency_limit, lifecycle_status, manual_disabled ON public.credentials FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();



\unrestrict tNHX0zcRwaeReb1mf5HgEeILhQrhAtff7r4ApUCQedh43k9qpEAB7GHfb9nEfKs


