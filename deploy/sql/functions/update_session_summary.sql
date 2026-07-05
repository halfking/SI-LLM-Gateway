-- ============================================
-- Function: update_session_summary
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.update_session_summary() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ DECLARE v_input_cost DECIMAL(12,6); v_output_cost DECIMAL(12,6); v_total_cost DECIMAL(12,6); v_prompt_tokens BIGINT; v_completion_tokens BIGINT; v_latency_ms INT; v_status VARCHAR(50); v_client_model VARCHAR(100); v_upstream_model VARCHAR(100); v_work_type VARCHAR(50); v_provider VARCHAR(50); BEGIN v_input_cost := COALESCE(NEW.input_cost, 0); v_output_cost := COALESCE(NEW.output_cost, 0); v_total_cost := COALESCE(NEW.total_cost, 0); v_prompt_tokens := COALESCE(NEW.prompt_tokens, 0); v_completion_tokens := COALESCE(NEW.completion_tokens, 0); v_latency_ms := COALESCE(NEW.latency_ms, 0); v_status := NEW.status; v_client_model := NEW.client_model; v_upstream_model := NEW.upstream_model; v_work_type := NEW.work_type; v_provider := NEW.provider; INSERT INTO session_summaries (session_key, tenant_id, first_request_at, last_request_at, request_count, success_count, error_count, total_cost_usd, input_cost_usd, output_cost_usd, total_prompt_tokens, total_completion_tokens, avg_latency_ms, min_latency_ms, max_latency_ms, models_used, work_types, providers, client_models, updated_at) VALUES (NEW.session_key, NEW.tenant_id, NEW.created_at, NEW.created_at, 1, CASE WHEN v_status = 'success' THEN 1 ELSE 0 END, CASE WHEN v_status != 'success' THEN 1 ELSE 0 END, v_total_cost, v_input_cost, v_output_cost, v_prompt_tokens, v_completion_tokens, v_latency_ms, v_latency_ms, v_latency_ms, ARRAY[v_upstream_model]::TEXT[], CASE WHEN v_work_type IS NOT NULL THEN ARRAY[v_work_type]::TEXT[] ELSE '{}'::TEXT[] END, CASE WHEN v_provider IS NOT NULL THEN ARRAY[v_provider]::TEXT[] ELSE '{}'::TEXT[] END, CASE WHEN v_client_model IS NOT NULL THEN ARRAY[v_client_model]::TEXT[] ELSE '{}'::TEXT[] END, NOW()) ON CONFLICT (session_key) DO UPDATE SET last_request_at = GREATEST(session_summaries.last_request_at, NEW.created_at), request_count = session_summaries.request_count + 1, success_count = session_summaries.success_count + CASE WHEN v_status = 'success' THEN 1 ELSE 0 END, error_count = session_summaries.error_count + CASE WHEN v_status != 'success' THEN 1 ELSE 0 END, total_cost_usd = session_summaries.total_cost_usd + v_total_cost, input_cost_usd = session_summaries.input_cost_usd + v_input_cost, output_cost_usd = session_summaries.output_cost_usd + v_output_cost, total_prompt_tokens = session_summaries.total_prompt_tokens + v_prompt_tokens, total_completion_tokens = session_summaries.total_completion_tokens + v_completion_tokens, avg_latency_ms = ((session_summaries.avg_latency_ms * session_summaries.request_count + v_latency_ms) / (session_summaries.request_count + 1))::INT, min_latency_ms = LEAST(session_summaries.min_latency_ms, v_latency_ms), max_latency_ms = GREATEST(session_summaries.max_latency_ms, v_latency_ms), models_used = array_unique_append(session_summaries.models_used, v_upstream_model), work_types = array_unique_append(session_summaries.work_types, v_work_type), providers = array_unique_append(session_summaries.providers, v_provider), client_models = array_unique_append(session_summaries.client_models, v_client_model), updated_at = NOW(); RETURN NEW; END; $$;



CREATE TABLE public.agent_relationships (
    src_agent_id bigint NOT NULL,
    dst_agent_id bigint NOT NULL,
    rel text NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_agent_rel CHECK ((rel = ANY (ARRAY['calls'::text, 'delegates'::text, 'depends_on'::text, 'similar_to'::text]))),
    CONSTRAINT chk_agent_rel_no_self CHECK ((src_agent_id <> dst_agent_id))
);



CREATE TABLE public.agents (
    id bigint NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    kind text NOT NULL,
    endpoint text NOT NULL,
    status text DEFAULT 'unknown'::text NOT NULL,
    capabilities jsonb DEFAULT '{}'::jsonb NOT NULL,
    version text DEFAULT '0.0.0'::text NOT NULL,
    auth_scheme text,
    last_heartbeat timestamp with time zone,
    registered_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_agents_auth CHECK (((auth_scheme IS NULL) OR (auth_scheme = ANY (ARRAY['bearer'::text, 'api_key'::text, 'mtls'::text, 'none'::text])))),
    CONSTRAINT chk_agents_kind CHECK ((kind = ANY (ARRAY['openclaw'::text, 'brandmind-go'::text, 'crm-go'::text, 'custom'::text]))),
    CONSTRAINT chk_agents_status CHECK ((status = ANY (ARRAY['healthy'::text, 'degraded'::text, 'down'::text, 'unknown'::text])))
);



CREATE SEQUENCE public.agents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.agents_id_seq OWNED BY public.agents.id;



CREATE TABLE public.analysis_events (
    id bigint NOT NULL,
    event_id text NOT NULL,
    type text NOT NULL,
    tenant_id text NOT NULL,
    session_id text,
    request_id text,
    payload jsonb DEFAULT '{}'::jsonb NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    worker text,
    attempts integer DEFAULT 0 NOT NULL,
    last_error text
);



CREATE SEQUENCE public.analysis_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.analysis_events_id_seq OWNED BY public.analysis_events.id;



CREATE TABLE public.api_key_auto_profile (
    api_key_id integer NOT NULL,
    profile text DEFAULT 'smart'::text NOT NULL,
    first_chosen_at timestamp with time zone DEFAULT now(),
    last_used_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT api_key_auto_profile_profile_check CHECK ((profile = ANY (ARRAY['smart'::text, 'speed_first'::text, 'cost_first'::text])))
);



COMMENT ON TABLE public.api_key_auto_profile IS 'Auto route: per-API-Key profile preference (sticky 30min)';



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



COMMENT ON TABLE public.api_key_model_cost IS 'Auto route: per-API-Key per-model 5min rolled-up cost + concurrency + score';



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



COMMENT ON COLUMN public.api_keys.status IS 'active | pending | disabled | throttled (auto-frozen) | revoked (permanent ban)';



COMMENT ON COLUMN public.api_keys.is_system IS 'System key - should not be disabled (e.g., admin login key)';



COMMENT ON COLUMN public.api_keys.rate_limit_concurrent IS 'Per-key concurrent request cap (NULL = use tier default)';



COMMENT ON COLUMN public.api_keys.rate_limit_tpm IS 'Tokens per minute cap (NULL = no limit)';



COMMENT ON COLUMN public.api_keys.key_tier IS 'system | production | default | applicant';



COMMENT ON COLUMN public.api_keys.key_ciphertext_kid IS 'kid that was used when key_ciphertext was last written (v1 AES-GCM envelope)';



COMMENT ON COLUMN public.api_keys.throttled_at IS 'Timestamp when the key was auto-throttled by anomaly detection';



COMMENT ON COLUMN public.api_keys.ewma_rpm_baseline IS 'Rolling EWMA baseline RPM for anomaly detection (7-day window)';



COMMENT ON COLUMN public.api_keys.remark IS 'Reason for key creation (system-created keys must explain why)';



COMMENT ON COLUMN public.api_keys.key_alias IS 'Optional human-readable alias for the key';



COMMENT ON COLUMN public.api_keys.total_requests IS 'Cumulative count of requests authenticated by this key';



COMMENT ON COLUMN public.api_keys.total_prompt_tokens IS 'Cumulative prompt token count';



COMMENT ON COLUMN public.api_keys.total_completion_tokens IS 'Cumulative completion token count';



COMMENT ON COLUMN public.api_keys.total_cost_usd IS 'Cumulative cost in USD';



COMMENT ON COLUMN public.api_keys.last_request_at IS 'When this key last made a request (denormalized from usage_ledger)';



CREATE SEQUENCE public.api_keys_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.api_keys_id_seq OWNED BY public.api_keys.id;



CREATE TABLE public.applications (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL,
    owner_user text,
    data_sensitivity text DEFAULT 'internal'::text NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    default_client_profile text,
    allowed_models_json jsonb,
    CONSTRAINT applications_data_sensitivity_check CHECK ((data_sensitivity = ANY (ARRAY['public'::text, 'internal'::text, 'confidential'::text])))
);



CREATE SEQUENCE public.applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.applications_id_seq OWNED BY public.applications.id;



CREATE TABLE public.approval_queue (
    id uuid NOT NULL,
    session_id text NOT NULL,
    tenant_id text NOT NULL,
    request_id text NOT NULL,
    detect_result jsonb NOT NULL,
    snapshot jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    approved_by text,
    approved_at timestamp with time zone,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    CONSTRAINT approval_queue_status_chk CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'timeout'::text])))
);

ALTER TABLE ONLY public.approval_queue FORCE ROW LEVEL SECURITY;



CREATE TABLE public.armor_judgments (
    id bigint NOT NULL,
    request_id text NOT NULL,
    tenant_id text NOT NULL,
    check_type text NOT NULL,
    decision text NOT NULL,
    source text NOT NULL,
    pattern_ids text[],
    judge_model text,
    score real,
    threshold real,
    mode text DEFAULT 'observe'::text NOT NULL,
    latency_ms integer DEFAULT 0 NOT NULL,
    prompt_sha256 text,
    snippet text,
    reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_armor_check CHECK ((check_type = ANY (ARRAY['prompt_inject'::text, 'pii'::text, 'hallucination'::text]))),
    CONSTRAINT chk_armor_decision CHECK ((decision = ANY (ARRAY['safe'::text, 'warn'::text, 'block'::text]))),
    CONSTRAINT chk_armor_mode CHECK ((mode = ANY (ARRAY['observe'::text, 'enforce'::text]))),
    CONSTRAINT chk_armor_source CHECK ((source = ANY (ARRAY['pattern'::text, 'judge'::text])))
);



CREATE SEQUENCE public.armor_judgments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.armor_judgments_id_seq OWNED BY public.armor_judgments.id;



CREATE TABLE public.asset_relationships (
    src_kind text NOT NULL,
    src_ref_id bigint NOT NULL,
    dst_kind text NOT NULL,
    dst_ref_id bigint NOT NULL,
    rel text NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_asset_rel_type CHECK ((rel = ANY (ARRAY['depends_on'::text, 'calls'::text, 'similar_to'::text])))
);



CREATE TABLE public.assets (
    kind text NOT NULL,
    ref_id bigint NOT NULL,
    tenant_id text NOT NULL,
    name text NOT NULL,
    owner text,
    team text,
    cost_center text,
    tags jsonb DEFAULT '{}'::jsonb NOT NULL,
    health_state text DEFAULT 'unknown'::text NOT NULL,
    version text DEFAULT '0.0.0'::text NOT NULL,
    registered_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    CONSTRAINT chk_assets_health CHECK ((health_state = ANY (ARRAY['healthy'::text, 'degraded'::text, 'down'::text, 'unknown'::text]))),
    CONSTRAINT chk_assets_kind CHECK ((kind = ANY (ARRAY['llm_endpoint'::text, 'mcp_server'::text, 'agent'::text])))
);



CREATE TABLE public.attachments (
    id text NOT NULL,
    tenant_id text NOT NULL,
    request_id text NOT NULL,
    attachment_type text NOT NULL,
    media_type text NOT NULL,
    file_size bigint NOT NULL,
    file_path text NOT NULL,
    original_data_type text NOT NULL,
    original_url text,
    content_hash text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    metadata jsonb
);



CREATE TABLE public.auto_tune_audit (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    action text NOT NULL,
    old_limit integer,
    new_limit integer,
    reason text,
    peak_concurrent integer,
    p95_concurrent numeric(8,2),
    week_start timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    applied_by text
);



COMMENT ON TABLE public.auto_tune_audit IS 'Audit log for concurrency limit auto-tune actions (24h preview + auto-apply)';



CREATE SEQUENCE public.auto_tune_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.auto_tune_audit_id_seq OWNED BY public.auto_tune_audit.id;



CREATE TABLE public.background_tasks (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    task_type text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    status text DEFAULT 'running'::text NOT NULL,
    request_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    result_json jsonb,
    error text,
    started_at timestamp with time zone DEFAULT now() NOT NULL,
    finished_at timestamp with time zone
);



CREATE TABLE public.background_tasks_duplicates (
    id bigint NOT NULL,
    tenant_id text NOT NULL,
    task_type text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    status text NOT NULL,
    request_json jsonb NOT NULL,
    result_json jsonb,
    error text,
    started_at timestamp with time zone NOT NULL,
    finished_at timestamp with time zone,
    removed_at timestamp with time zone DEFAULT now()
);



CREATE SEQUENCE public.background_tasks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.background_tasks_id_seq OWNED BY public.background_tasks.id;



CREATE TABLE public.billing_orders (
    id bigint NOT NULL,
    order_no character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    order_type character varying(16) NOT NULL,
    status character varying(16) DEFAULT 'pending'::character varying NOT NULL,
    amount_cents integer NOT NULL,
    credits bigint NOT NULL,
    plan_id integer,
    package_id integer,
    payment_channel character varying(16) DEFAULT 'alipay'::character varying NOT NULL,
    qr_payload text DEFAULT ''::text NOT NULL,
    qr_url text DEFAULT ''::text NOT NULL,
    paid_at timestamp with time zone,
    expires_at timestamp with time zone NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT billing_orders_order_type_check CHECK (((order_type)::text = ANY (ARRAY[('subscribe'::character varying)::text, ('topup'::character varying)::text]))),
    CONSTRAINT billing_orders_payment_channel_check CHECK (((payment_channel)::text = ANY (ARRAY[('alipay'::character varying)::text, ('wechat'::character varying)::text, ('manual'::character varying)::text]))),
    CONSTRAINT billing_orders_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('paid'::character varying)::text, ('cancelled'::character varying)::text, ('expired'::character varying)::text])))
);



CREATE SEQUENCE public.billing_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.billing_orders_id_seq OWNED BY public.billing_orders.id;




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
    per_attempt_latency_ms integer,
    extracted_upstream_status_code integer,
    diagnosed_error_kind text
);



COMMENT ON COLUMN public.candidate_failure_logs.per_attempt_latency_ms IS 'Latency of the single upstream call.';




CREATE TABLE public.credential_capabilities (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    capability text NOT NULL,
    supported boolean DEFAULT false NOT NULL,
    last_tested_at timestamp with time zone,
    evidence_json jsonb,
    CONSTRAINT credential_capabilities_capability_check CHECK ((capability = ANY (ARRAY['tool_use'::text, 'vision'::text, 'streaming'::text, 'prompt_caching'::text, 'structured_output'::text, 'long_context'::text, 'json_mode'::text, 'batch'::text])))
);



CREATE SEQUENCE public.credential_capabilities_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credential_capabilities_id_seq OWNED BY public.credential_capabilities.id;



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



CREATE SEQUENCE public.credential_health_checks_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credential_health_checks_id_seq OWNED BY public.credential_health_checks.id;



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



COMMENT ON TABLE public.credential_model_bindings IS 'Many-to-many: which credential can access which model, with routing/pricing attrs';



COMMENT ON COLUMN public.credential_model_bindings.billing_mode IS 'Billing mode: token (PAYG per-1M) | token_plan (prepaid credits/package) | code_plan (subscription, monthly fee + bundle) | free (rate=0) | per_token/per_request/monthly (legacy aliases)';



COMMENT ON COLUMN public.credential_model_bindings.plan_meta IS 'Subscription/plan metadata: {monthly_cny, included_tokens, tier, validity_days, modality, etc.}. Mirrors pricing_plans.plan_json at offer level.';



COMMENT ON COLUMN public.credential_model_bindings.transient_failure_count IS '触发验证时的失败计数快照（非实时；实时计数在 Redis 滑动窗口）';



COMMENT ON COLUMN public.credential_model_bindings.pending_verification IS '是否有进行中的双重验证';



CREATE SEQUENCE public.credential_model_bindings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credential_model_bindings_id_seq OWNED BY public.credential_model_bindings.id;



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



COMMENT ON TABLE public.credential_model_call_history IS 'Aggregated call history per (credential, model) in 1-minute windows. Used for intelligent availability tracking, continuous failure detection, and concurrency auto-tuning.';



COMMENT ON COLUMN public.credential_model_call_history.error_rate_limit_count IS '429 rate limit errors - triggers concurrency reduction';



COMMENT ON COLUMN public.credential_model_call_history.error_concurrent_count IS '503 concurrent overload errors - triggers concurrency reduction';



COMMENT ON COLUMN public.credential_model_call_history.avg_concurrent IS 'Average concurrent requests in this window - used for auto-scaleup';



COMMENT ON COLUMN public.credential_model_call_history.peak_concurrent IS 'Peak concurrent requests in this window - used for capacity planning';



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



COMMENT ON TABLE public.credential_model_index IS '5-min rollup of per-credential health metrics. Monthly partitions (heap). Data older than 7 days is archived to credential_model_index_archive (columnar) by archive_credential_model_index() — see migration 317.';




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



CREATE TABLE public.credential_model_peak_1m (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    peak_concurrent integer DEFAULT 0 NOT NULL,
    avg_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL
);



COMMENT ON TABLE public.credential_model_peak_1m IS 'Per-minute peak concurrency per credential-model pair (used by auto-tune)';



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



COMMENT ON TABLE public.credential_model_stats_1m IS 'Per-minute aggregated routing stats, used for sliding window queries';



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



COMMENT ON TABLE public.credential_model_weekly_peak IS 'Weekly aggregated peak concurrency for auto-tune suggestions';



CREATE TABLE public.credential_probe_configs (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    probe_model text NOT NULL,
    priority integer DEFAULT 1,
    enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now()
);



CREATE SEQUENCE public.credential_probe_configs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credential_probe_configs_id_seq OWNED BY public.credential_probe_configs.id;




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



CREATE SEQUENCE public.credential_probes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credential_probes_id_seq OWNED BY public.credential_probes.id;



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



CREATE SEQUENCE public.credential_quota_usage_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credential_quota_usage_id_seq OWNED BY public.credential_quota_usage.id;



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



CREATE SEQUENCE public.credential_quotas_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credential_quotas_id_seq OWNED BY public.credential_quotas.id;



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



COMMENT ON COLUMN public.credentials.api_models_ok IS '最近一次模型清单 API 拉取是否成功（NULL=未验证）';



COMMENT ON COLUMN public.credentials.api_models_last_checked_at IS '最近一次模型清单 API 验证时间';



COMMENT ON COLUMN public.credentials.api_models_error IS '最近一次模型清单 API 验证失败原因（HTTP 状态码 + 错误摘要，已脱敏）';



COMMENT ON COLUMN public.credentials.balance_check_endpoint IS 'URL template to check remaining balance';



COMMENT ON COLUMN public.credentials.pool_group IS 'free | shared | dedicated | NULL';



COMMENT ON COLUMN public.credentials.acquisition_source IS 'Free pool: signup | env | oauth | mirrored | discovered | no_key | manual';



COMMENT ON COLUMN public.credentials.acquisition_detail IS 'Free pool source detail: env var name, mirror source label, oauth file, signup URL, etc.';



COMMENT ON COLUMN public.credentials.concurrency_limit_auto IS 'Algorithm-recommended concurrency limit. Adjusted dynamically based on 429/503 errors and success rate. Read priority: concurrency_limit (manual) > concurrency_limit_auto > default 5.';



COMMENT ON COLUMN public.credentials.fp_slot_limit IS 'Fingerprint slot pool size: number of distinct virtual user identities this credential can simulate. 0 = unlimited. Distinct from concurrency_limit which controls in-flight request count.';



COMMENT ON CONSTRAINT credentials_fp_slot_vs_concurrency ON public.credentials IS 'fp_slot_limit (distinct user identities) MUST be <= concurrency_limit (in-flight requests). Otherwise the fingerprint pool exceeds the upstream capacity, defeating anti-rate-limit.';



CREATE SEQUENCE public.credentials_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credentials_id_seq OWNED BY public.credentials.id;



CREATE TABLE public.credit_ledger (
    id bigint NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
)
PARTITION BY RANGE (created_at);



CREATE SEQUENCE public.credit_ledger_partitioned_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credit_ledger_partitioned_id_seq OWNED BY public.credit_ledger.id;



CREATE TABLE public.credit_ledger_2026_06 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);



CREATE TABLE public.credit_ledger_2026_07 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);



CREATE TABLE public.credit_ledger_2026_08 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);



CREATE TABLE public.credit_ledger_old (
    id bigint NOT NULL,
    tenant_id character varying(64) NOT NULL,
    entry_type character varying(32) NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying(32),
    ref_id character varying(128),
    note text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying(32),
    CONSTRAINT credit_ledger_entry_type_check CHECK (((entry_type)::text = ANY (ARRAY[('consume'::character varying)::text, ('topup'::character varying)::text, ('subscribe'::character varying)::text, ('adjust'::character varying)::text, ('refund'::character varying)::text])))
);



CREATE SEQUENCE public.credit_ledger_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.credit_ledger_id_seq OWNED BY public.credit_ledger_old.id;



CREATE SEQUENCE public.request_logs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



CREATE TABLE public.request_logs (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    upstream_status_code integer,
    test_col text[] DEFAULT '{}'::text[] NOT NULL,
    test_tab_indent text,
    provider_model text,
    has_attachments boolean DEFAULT false,
    attachment_count integer DEFAULT 0,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
)
PARTITION BY RANGE (ts);

ALTER TABLE ONLY public.request_logs FORCE ROW LEVEL SECURITY;



COMMENT ON COLUMN public.request_logs.cost_display IS 'Request-level displayed cost in its native currency; may differ from cost_usd when provider pricing is not USD.';



COMMENT ON COLUMN public.request_logs.cost_currency IS 'Currency for request_logs.cost_display, e.g. USD/CNY.';



COMMENT ON COLUMN public.request_logs.is_auto_request IS 'Auto route: was this request model=auto?';



COMMENT ON COLUMN public.request_logs.task_type IS 'Auto route: classified task type (chat/reasoning/code/...)';



COMMENT ON COLUMN public.request_logs.auto_profile IS 'Auto route: profile used (smart/speed_first/cost_first)';



COMMENT ON COLUMN public.request_logs.auto_decision IS 'Auto route: top-N candidates + chosen model + scoring breakdown';



COMMENT ON COLUMN public.request_logs.auto_confidence IS 'Auto route: classification confidence 0-1';



COMMENT ON COLUMN public.request_logs.parent_request_id IS 'Round 47 (2026-06-18): the pre-compression request_id when compressor rewrote the body. NULL for uncompressed rows. Single-level chain only (child has at most 1 parent).';



COMMENT ON COLUMN public.request_logs.compression_reason IS 'Round 47 (2026-06-18): why compression fired. mode_1_auto_threshold = body > cand.ContextWindow × 0.8 × 3.5 (LLM_GATEWAY_COMPRESSION_MODE=1). mode_2_on_4xx = upstream 4xx context_length_exceeded (LLM_GATEWAY_COMPRESSION_MODE=2). NULL = no compression event, OR pre-request trim happened without 4xx (T-NEW-4). See compression_meta.trim_phase for explicit phase tagging.';



COMMENT ON COLUMN public.request_logs.compression_strategy IS 'Round 47 (2026-06-18): which decompression path succeeded. mechanical_trim = oldest-pair drop (transform/ctx_compress.go). memora_l1_inject = dynamic_context user message from Memora /product/search. llm_summary = 1M-context model summary. noop = attempted but skipped (e.g. warmup_min_facts guard).';



COMMENT ON COLUMN public.request_logs.compression_meta IS 'Round 47 (2026-06-18): compression telemetry. 4xx recovery fields (T-NEW-2): tokens_before/after, bytes_before/after, context_window_used, threshold_bytes, dropped_messages, summary_chars, model_used, latency_ms, memora_facts_used, warmup_skipped, first_user_retained, system_retained, reason_detail. Pre-request trim fields (T-NEW-4): trim_phase="pre_request", phases=["pre_request_trim"] or ["pre_request_trim","4xx_recovery"], reason_detail="pre-request trim (cand.ContextWindow × 0.85 × 3.5 threshold)". See v7 §3.2.';



COMMENT ON COLUMN public.request_logs.outbound_body IS 'v3 (2026-06-19): LLM wire body JSONB — what was actually forwarded to the
     upstream provider. NULL = no session compressor active (outbound == client).
     Differs from request_body when v3 session-level delta-append or proactive
     sliding-window summary rewrote the body before forwarding.';



COMMENT ON COLUMN public.request_logs.outbound_msg_count IS 'v3 (2026-06-19): Message count inside outbound_body (including system).
     Compare to the client message count in request_body to measure delta.';



COMMENT ON COLUMN public.request_logs.outbound_token_est IS 'v3 (2026-06-19): Estimated token count for outbound_body using the
     3.5 chars/token heuristic (same as compressor/estimator.go). Used to
     audit sliding-window threshold decisions in request_logs UI.';



COMMENT ON COLUMN public.request_logs.outbound_msg_hashes IS 'v3 (2026-06-19): Per-message fingerprint array [{index, sha256}] for
     outbound_body messages. The next request with the same gw_session_id
     reads this column to run LCS diff and find the incremental message tail,
     enabling delta-append without full re-send of conversation history.';



COMMENT ON COLUMN public.request_logs.upstream_finish_reason IS '2026-06-19 T-NEW-7: the SOLE home for the upstream finish_reason
     (stop, tool_calls, length, end_turn, function_call, max_tokens, …).
     NULL means the stream ended without a finish_reason (e.g. truncated
     pre-finish).  Populated for BOTH success and failure rows.
     This column REPLACES the prior use of failure_detail_code for
     finish reasons; see the migration header for the full rationale.';



COMMENT ON COLUMN public.request_logs.tool_calls IS 'Structured tool calls from assistant message. OpenAI format: [{id, type, function: {name, arguments}}]. Populated for both streaming and non-streaming responses.';



COMMENT ON COLUMN public.request_logs.upstream_status_code IS 'HTTP status code returned by upstream (NULL = network-level error, success, or unknown). Populated from the last attempt in executor.go and persisted via telemetry/client.go INSERT/UPDATE.';



CREATE VIEW public.customer_cost_view AS
 SELECT akmc.api_key_id,
    ak.key_alias,
    ak.tenant_id,
    ak.application_id,
    sum(
        CASE
            WHEN (akmc.bucket >= (now() - '01:00:00'::interval)) THEN akmc.cost_usd
            ELSE (0)::numeric
        END) AS cost_usd_1h,
    sum(
        CASE
            WHEN (akmc.bucket >= (now() - '24:00:00'::interval)) THEN akmc.cost_usd
            ELSE (0)::numeric
        END) AS cost_usd_24h,
    sum(
        CASE
            WHEN (akmc.bucket >= (now() - '7 days'::interval)) THEN akmc.cost_usd
            ELSE (0)::numeric
        END) AS cost_usd_7d,
    sum(akmc.requests_total) AS total_auto_requests,
    sum(akmc.requests_success) AS total_auto_success,
    ( SELECT count(*) AS count
           FROM public.request_logs rl
          WHERE ((rl.api_key_id = akmc.api_key_id) AND (rl.is_auto_request = true) AND (rl.ts >= (now() - '00:05:00'::interval)) AND (rl.success IS NOT NULL) AND (rl.ts IS NOT NULL))) AS active_concurrent,
    max(akmc.concurrency_limit) AS concurrency_limit,
    avg(
        CASE
            WHEN (akmc.bucket >= (now() - '01:00:00'::interval)) THEN akmc.pressure_ratio
            ELSE NULL::numeric
        END) AS avg_pressure_1h,
    max(akmc.score_smart) AS best_score_smart,
    max(akmc.score_speed_first) AS best_score_speed_first,
    max(akmc.score_cost_first) AS best_score_cost_first,
    max(akmc.last_request_at) AS last_request_at
   FROM (public.api_key_model_cost akmc
     JOIN public.api_keys ak ON ((ak.id = akmc.api_key_id)))
  GROUP BY akmc.api_key_id, ak.key_alias, ak.tenant_id, ak.application_id;



COMMENT ON VIEW public.customer_cost_view IS 'Auto route: per-API-Key customer cost dashboard (1h/24h/7d windows + concurrency + scores). active_concurrent is computed live from request_logs (5min window).';



CREATE TABLE public.goal_sessions (
    id integer NOT NULL,
    session_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    state character varying(32) DEFAULT 'active'::character varying NOT NULL,
    original_goal text NOT NULL,
    retry_count integer DEFAULT 0,
    decision_count integer DEFAULT 0,
    auto_continue_count integer DEFAULT 0,
    last_activity_at timestamp without time zone DEFAULT now(),
    completed_at timestamp without time zone,
    audit_result jsonb,
    created_at timestamp without time zone DEFAULT now()
);



CREATE SEQUENCE public.goal_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.goal_sessions_id_seq OWNED BY public.goal_sessions.id;



CREATE TABLE public.handoff_logs (
    id integer NOT NULL,
    session_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    trigger_reason character varying(64) NOT NULL,
    tokens_at_handoff integer NOT NULL,
    context_window integer,
    handoff_prompt text,
    new_session_id character varying(64),
    created_at timestamp without time zone DEFAULT now()
);



CREATE SEQUENCE public.handoff_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.handoff_logs_id_seq OWNED BY public.handoff_logs.id;



CREATE TABLE public.intent_aggregates (
    tenant_id text NOT NULL,
    intent_kind text NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    last_updated timestamp with time zone DEFAULT now() NOT NULL
);



CREATE TABLE public.internal_service_keys (
    service_id text NOT NULL,
    secret_hash text NOT NULL,
    description text,
    enabled boolean DEFAULT true NOT NULL,
    last_used_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    rotated_at timestamp with time zone,
    rotation_notes text
);



COMMENT ON TABLE public.internal_service_keys IS 'Registry of HMAC secrets for internal service-to-service authentication.
     The actual secret is stored in INTERNAL_SERVICE_KEYS_JSON env var (not here).
     This table tracks registration metadata and last-used timestamps for audit.';



CREATE TABLE public.key_applications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    client_ip inet NOT NULL,
    fingerprint text NOT NULL,
    contact text NOT NULL,
    purpose text,
    status text DEFAULT 'pending'::text NOT NULL,
    issued_key_id bigint,
    admin_notes text,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    expires_at timestamp with time zone DEFAULT (now() + '24:00:00'::interval) NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT key_applications_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'expired'::text])))
);



CREATE TABLE public.key_rpm_daily (
    api_key_id bigint NOT NULL,
    day_bucket date NOT NULL,
    peak_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    avg_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    request_count bigint DEFAULT 0 NOT NULL
);



CREATE TABLE public.local_models (
    id bigint NOT NULL,
    runtime_id bigint NOT NULL,
    canonical_id bigint,
    raw_name text NOT NULL,
    quantization text,
    size_bytes bigint,
    family text,
    parameters_b numeric(8,2),
    loaded boolean DEFAULT false NOT NULL,
    keep_alive_seconds integer DEFAULT 0 NOT NULL,
    last_used_at timestamp with time zone
);



CREATE SEQUENCE public.local_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.local_models_id_seq OWNED BY public.local_models.id;



CREATE TABLE public.local_runtimes (
    id bigint NOT NULL,
    host_code text NOT NULL,
    runtime_type text NOT NULL,
    base_url text NOT NULL,
    mode text DEFAULT 'direct'::text NOT NULL,
    status text DEFAULT 'unknown'::text NOT NULL,
    gpu_info_json jsonb,
    vram_total_mb integer,
    vram_used_mb integer,
    ram_total_mb integer,
    last_heartbeat_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT local_runtimes_mode_check CHECK ((mode = ANY (ARRAY['direct'::text, 'agent'::text]))),
    CONSTRAINT local_runtimes_runtime_type_check CHECK ((runtime_type = ANY (ARRAY['ollama'::text, 'vllm'::text, 'llamacpp'::text, 'lmstudio'::text, 'mlx'::text]))),
    CONSTRAINT local_runtimes_status_check CHECK ((status = ANY (ARRAY['unknown'::text, 'healthy'::text, 'degraded'::text, 'offline'::text])))
);



CREATE SEQUENCE public.local_runtimes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.local_runtimes_id_seq OWNED BY public.local_runtimes.id;



CREATE TABLE public.maas_settings (
    id integer DEFAULT 1 NOT NULL,
    cents_per_credit numeric(10,4) DEFAULT 0.1 NOT NULL,
    base_credits_per_1m bigint DEFAULT 10000 NOT NULL,
    currency_display character varying(8) DEFAULT 'CNY'::character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    alipay_account character varying(128) DEFAULT ''::character varying NOT NULL,
    wechat_mch_id character varying(128) DEFAULT ''::character varying NOT NULL,
    stub_alipay_qr_url text DEFAULT ''::text NOT NULL,
    stub_wechat_qr_url text DEFAULT ''::text NOT NULL,
    base_credits_per_1m_out bigint,
    base_credits_per_1m_cache_in bigint,
    base_credits_per_1m_cache_out bigint,
    global_discount numeric(6,4) DEFAULT 1.0 NOT NULL,
    CONSTRAINT maas_settings_id_check CHECK ((id = 1))
);



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



CREATE SEQUENCE public.model_aliases_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.model_aliases_id_seq OWNED BY public.model_aliases.id;



CREATE VIEW public.model_cost_per_task_view AS
 SELECT mcp.canonical_id,
    mcp.raw_model,
    sum(mcp.cost_usd) AS total_cost_usd,
    sum((mcp.tokens_input + mcp.tokens_output)) AS total_tokens,
        CASE
            WHEN (sum((mcp.tokens_input + mcp.tokens_output)) > (0)::numeric) THEN ((sum(mcp.cost_usd) / sum((mcp.tokens_input + mcp.tokens_output))) * (1000000)::numeric)
            ELSE (0)::numeric
        END AS avg_cost_per_1m_usd,
        CASE
            WHEN (sum(mcp.requests_total) > 0) THEN ((sum(mcp.requests_success))::numeric / (sum(mcp.requests_total))::numeric)
            ELSE (0)::numeric
        END AS success_rate,
    ( SELECT avg(rl.latency_ms) AS avg
           FROM public.request_logs rl
          WHERE ((rl.outbound_model = mcp.raw_model) AND (rl.success = true) AND (rl.ts >= (now() - '7 days'::interval)))) AS avg_latency_ms,
    sum(mcp.requests_total) AS total_requests,
    count(DISTINCT mcp.api_key_id) AS unique_api_keys
   FROM public.api_key_model_cost mcp
  WHERE (mcp.bucket >= (now() - '7 days'::interval))
  GROUP BY mcp.canonical_id, mcp.raw_model;



COMMENT ON VIEW public.model_cost_per_task_view IS 'Auto route: per-model aggregated cost for last 7 days';



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



CREATE SEQUENCE public.model_discovery_runs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.model_discovery_runs_id_seq OWNED BY public.model_discovery_runs.id;



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



CREATE TABLE public.model_fingerprints (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint NOT NULL,
    fingerprint_hash text NOT NULL,
    sampled_features_json jsonb,
    last_verified_at timestamp with time zone,
    drift_detected boolean DEFAULT false NOT NULL
);



CREATE SEQUENCE public.model_fingerprints_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.model_fingerprints_id_seq OWNED BY public.model_fingerprints.id;



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



CREATE SEQUENCE public.model_lifecycle_jobs_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.model_lifecycle_jobs_id_seq OWNED BY public.model_lifecycle_jobs.id;




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




CREATE TABLE public.provider_models (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    raw_model_name text NOT NULL,
    canonical_id bigint,
    standardized_name text,
    outbound_model_name text,
    available boolean DEFAULT true NOT NULL,
    unavailable_reason text,
    unavailable_at timestamp with time zone,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);



COMMENT ON TABLE public.provider_models IS 'Provider-exposed models: one row per (provider, raw_model_name)';



COMMENT ON COLUMN public.provider_models.canonical_id IS 'FK to models_canonical.id for canonical name resolution';



CREATE VIEW public.model_offers AS
 SELECT cmb.id,
    cmb.credential_id,
    pm.canonical_id,
    pm.raw_model_name,
    cmb.success_rate,
    cmb.p95_latency_ms,
    cmb.available,
    pm.last_seen_at,
    cmb.routing_tier,
    cmb.weight,
    cmb.unit_price_in_per_1m,
    cmb.unit_price_out_per_1m,
    cmb.currency,
    pm.outbound_model_name,
    cmb.cache_read_price_per_1m,
    cmb.cache_write_price_per_1m,
    pm.standardized_name,
    cmb.unavailable_reason,
    cmb.unavailable_at,
    cmb.billing_mode,
    cmb.pricing_source,
    cmb.pricing_updated_at,
    cmb.manual_priority,
    cmb.active_sessions,
    cmb.consecutive_failures,
    cmb.admin_protected
   FROM (public.credential_model_bindings cmb
     JOIN public.provider_models pm ON ((pm.id = cmb.provider_model_id)));



COMMENT ON COLUMN public.model_offers.billing_mode IS 'Billing mode: token (PAYG per-1M) | token_plan (prepaid credits/package) | code_plan (subscription, monthly fee + bundle) | free (rate=0) | per_token/per_request/monthly (legacy aliases)';



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



COMMENT ON COLUMN public.model_offers_legacy.cache_read_price_per_1m IS 'Per-million-token price for cache reads (NULL = use unit_price_in_per_1m)';



COMMENT ON COLUMN public.model_offers_legacy.cache_write_price_per_1m IS 'Per-million-token price for cache writes (NULL = use unit_price_in_per_1m)';



COMMENT ON COLUMN public.model_offers_legacy.standardized_name IS 'Standardized model name in format: family-version[-feature], e.g. "minimax-m2.7", "glm-4.5-flash", "claude-opus-4.8". Auto-filled on discovery, can be manually edited.';



COMMENT ON COLUMN public.model_offers_legacy.billing_mode IS 'per_token | per_request | monthly | free';



COMMENT ON COLUMN public.model_offers_legacy.pricing_source IS 'manual | scraped | inherited';



CREATE SEQUENCE public.model_offers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.model_offers_id_seq OWNED BY public.model_offers_legacy.id;




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



COMMENT ON TABLE public.model_probe_state IS 'Per-(credential, model) probe consensus state. 3 consecutive successes to recover; 3 consecutive failures to confirm-broken.';



COMMENT ON COLUMN public.model_probe_state.consecutive_successes IS 'Counter; resets to 0 on any failure. State flips to healthy_confirmed when this hits 3.';



COMMENT ON COLUMN public.model_probe_state.consecutive_failures IS 'Counter; resets to 0 on any success. Stops probing when this hits 3 (broken_confirmed).';



COMMENT ON COLUMN public.model_probe_state.verification_attempt_1_at IS '防闪断第一次验证时间（阈值触发后约2秒）';



COMMENT ON COLUMN public.model_probe_state.verification_attempt_2_at IS '防闪断第二次验证时间（第一次后约3秒）';



COMMENT ON COLUMN public.model_probe_state.verification_result_1 IS '第一次验证结果';



COMMENT ON COLUMN public.model_probe_state.verification_result_2 IS '第二次验证结果';



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



CREATE SEQUENCE public.model_reconcile_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.model_reconcile_log_id_seq OWNED BY public.model_reconcile_log.id;



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



COMMENT ON TABLE public.model_task_index IS 'Auto route: per-model-per-task 5min rolled-up performance (success/latency/cost)';



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



COMMENT ON COLUMN public.models_canonical.input_price_cny IS 'Input price in CNY per million tokens (0 = not set/unknown)';



COMMENT ON COLUMN public.models_canonical.output_price_cny IS 'Output price in CNY per million tokens (0 = not set/unknown)';



COMMENT ON COLUMN public.models_canonical.released_at IS '模型发布日期，用于 version_recency 评分维度（高难度任务偏好最新版，普通任务偏好次新版）';



COMMENT ON COLUMN public.models_canonical.strengths IS '运营标注的优势方向数组，用于 strength_match 评分维度（比 tags 更精准）';



COMMENT ON COLUMN public.models_canonical.cost_tier IS '成本粗评：free/low/medium/high/premium，用于快速筛选和展示';



COMMENT ON COLUMN public.models_canonical.multimodal_caps IS '多模态能力细粒度标签：vision/audio/image_gen/video/embedding 等';



COMMENT ON COLUMN public.models_canonical.version_rank IS '版本级次：1=最新, 2=次新, 3=稳定版... 用于路由策略（普通任务偏次新，高难度偏最新）';



CREATE SEQUENCE public.models_canonical_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.models_canonical_id_seq OWNED BY public.models_canonical.id;



CREATE TABLE public.ops_model_offers_backup (
    backup_id bigint NOT NULL,
    run_tag text NOT NULL,
    backed_at timestamp with time zone DEFAULT now() NOT NULL,
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    raw_model_name text NOT NULL,
    p95_latency_ms integer,
    success_rate numeric(5,4),
    available boolean NOT NULL,
    last_seen_at timestamp with time zone NOT NULL
);



CREATE SEQUENCE public.ops_model_offers_backup_backup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.ops_model_offers_backup_backup_id_seq OWNED BY public.ops_model_offers_backup.backup_id;



CREATE TABLE public.output_compliance_audit (
    id bigint NOT NULL,
    tenant_id character varying(255) NOT NULL,
    request_id character varying(255) NOT NULL,
    session_key character varying(255),
    detected_at timestamp with time zone DEFAULT now(),
    issue_type character varying(50) NOT NULL,
    issue_subtype character varying(50),
    severity integer NOT NULL,
    evidence text,
    location character varying(100),
    score numeric(5,4),
    action_taken character varying(20) NOT NULL,
    redacted boolean DEFAULT false,
    blocked boolean DEFAULT false,
    original_output text,
    redacted_output text,
    model character varying(100),
    client_ip character varying(45),
    CONSTRAINT output_compliance_audit_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);



CREATE SEQUENCE public.output_compliance_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.output_compliance_audit_id_seq OWNED BY public.output_compliance_audit.id;



CREATE TABLE public.output_compliance_policies (
    id integer NOT NULL,
    tenant_id character varying(255) NOT NULL,
    enabled boolean DEFAULT true,
    enforcement_mode character varying(20) DEFAULT 'observe'::character varying,
    check_pii boolean DEFAULT true,
    check_toxicity boolean DEFAULT true,
    check_bias boolean DEFAULT false,
    check_hallucination boolean DEFAULT false,
    pii_threshold numeric(3,2) DEFAULT 0.7,
    toxicity_threshold numeric(3,2) DEFAULT 0.7,
    bias_threshold numeric(3,2) DEFAULT 0.6,
    hallucination_threshold numeric(3,2) DEFAULT 0.7,
    action_on_pii character varying(20) DEFAULT 'redact'::character varying,
    action_on_toxicity character varying(20) DEFAULT 'warn'::character varying,
    action_on_bias character varying(20) DEFAULT 'log'::character varying,
    action_on_hallucination character varying(20) DEFAULT 'log'::character varying,
    auto_redact boolean DEFAULT true,
    redact_email boolean DEFAULT true,
    redact_phone boolean DEFAULT true,
    redact_id_card boolean DEFAULT true,
    redact_credit_card boolean DEFAULT true,
    strict_mode boolean DEFAULT false,
    log_all_outputs boolean DEFAULT false,
    whitelist_patterns text[],
    total_checks integer DEFAULT 0,
    total_issues integer DEFAULT 0,
    total_redactions integer DEFAULT 0,
    last_check_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(255),
    updated_by character varying(255)
);



CREATE SEQUENCE public.output_compliance_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.output_compliance_policies_id_seq OWNED BY public.output_compliance_policies.id;



CREATE VIEW public.output_compliance_stats_today AS
 SELECT output_compliance_audit.tenant_id,
    count(*) AS total_issues,
    count(*) FILTER (WHERE (output_compliance_audit.redacted = true)) AS redacted_count,
    count(*) FILTER (WHERE (output_compliance_audit.blocked = true)) AS blocked_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'pii'::text)) AS pii_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'toxic'::text)) AS toxic_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'bias'::text)) AS bias_count,
    count(*) FILTER (WHERE ((output_compliance_audit.issue_type)::text = 'hallucination'::text)) AS hallucination_count,
    avg(output_compliance_audit.severity) AS avg_severity,
    max(output_compliance_audit.severity) AS max_severity
   FROM public.output_compliance_audit
  WHERE (output_compliance_audit.detected_at >= CURRENT_DATE)
  GROUP BY output_compliance_audit.tenant_id;



CREATE TABLE public.passive_probe_state (
    credential_id integer NOT NULL,
    raw_model_name text NOT NULL,
    error_kind text NOT NULL,
    consecutive_count integer DEFAULT 0 NOT NULL,
    total_recent_count integer DEFAULT 0 NOT NULL,
    window_total_count integer DEFAULT 0 NOT NULL,
    first_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    last_seen_at timestamp with time zone DEFAULT now() NOT NULL,
    in_reviewing boolean DEFAULT false NOT NULL,
    reviewing_until timestamp with time zone,
    final_marked_at timestamp with time zone,
    unavailable_reason text,
    last_response_body_preview text
);



COMMENT ON TABLE public.passive_probe_state IS 'v5: Passive observation state for Layer 5. Accumulates consecutive errors from request_logs for the secondary-verification trigger (consecutive>=3 or error_rate>=0.6).';



CREATE TABLE public.pii_patterns (
    id integer NOT NULL,
    pattern_name character varying(100) NOT NULL,
    pattern_type character varying(50) NOT NULL,
    regex_pattern text NOT NULL,
    description text,
    enabled boolean DEFAULT true,
    severity integer DEFAULT 7,
    redact_format character varying(100),
    created_at timestamp with time zone DEFAULT now()
);



CREATE SEQUENCE public.pii_patterns_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.pii_patterns_id_seq OWNED BY public.pii_patterns.id;




CREATE TABLE public.price_change_events (
    id bigint,
    old_plan_id bigint,
    new_plan_id bigint,
    delta_json jsonb,
    detected_at timestamp with time zone,
    notify_channel text,
    applied boolean
);




CREATE TABLE public.pricing_plans (
    id bigint NOT NULL,
    scope text NOT NULL,
    provider_id bigint,
    credential_id bigint,
    tenant_id text,
    model_canonical_id bigint,
    plan_type text NOT NULL,
    currency text DEFAULT 'USD'::text NOT NULL,
    plan_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    effective_from timestamp with time zone DEFAULT now() NOT NULL,
    effective_to timestamp with time zone,
    source text DEFAULT 'manual'::text NOT NULL,
    confidence numeric(4,3) DEFAULT 1.000,
    scraped_url text,
    offer_scope_key text GENERATED ALWAYS AS (((((((((((scope || ':'::text) || COALESCE((provider_id)::text, '-'::text)) || ':'::text) || COALESCE((credential_id)::text, '-'::text)) || ':'::text) || COALESCE(tenant_id, '-'::text)) || ':'::text) || COALESCE((model_canonical_id)::text, '-'::text)) || ':'::text) || plan_type)) STORED,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pricing_plans_plan_type_check CHECK ((plan_type = ANY (ARRAY['token'::text, 'token_plan'::text, 'code_plan'::text, 'agent_plan'::text, 'request'::text, 'seat'::text, 'compute_time'::text, 'flat_quota'::text, 'free'::text]))),
    CONSTRAINT pricing_plans_scope_check CHECK ((scope = ANY (ARRAY['provider'::text, 'credential'::text, 'tenant'::text]))),
    CONSTRAINT pricing_plans_source_check CHECK ((source = ANY (ARRAY['manual'::text, 'seed'::text, 'litellm'::text, 'scraped'::text, 'catalog'::text])))
);



COMMENT ON COLUMN public.pricing_plans.plan_type IS 'Plan type: token (PAYG per-1M) | token_plan (prepaid credits/package, NEW 2026-06-12) | code_plan (subscription) | agent_plan (agent bundle) | seat (per seat) | request (per request) | compute_time | flat_quota | free';



CREATE SEQUENCE public.pricing_plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.pricing_plans_id_seq OWNED BY public.pricing_plans.id;



CREATE TABLE public.pricing_refresh_log (
    id bigint NOT NULL,
    run_id text NOT NULL,
    run_ts timestamp with time zone DEFAULT now() NOT NULL,
    trigger text DEFAULT 'cron'::text NOT NULL,
    status text NOT NULL,
    before_summary jsonb NOT NULL,
    after_summary jsonb NOT NULL,
    diff_count integer DEFAULT 0 NOT NULL,
    new_offers integer DEFAULT 0 NOT NULL,
    removed_offers integer DEFAULT 0 NOT NULL,
    changed_offers integer DEFAULT 0 NOT NULL,
    artifacts_path text,
    feishu_sent boolean DEFAULT false NOT NULL,
    error_message text,
    duration_seconds integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);



COMMENT ON TABLE public.pricing_refresh_log IS 'Audit log for monthly pricing refresh cron job. Each run inserts one row.';



COMMENT ON COLUMN public.pricing_refresh_log.before_summary IS 'pricing/summary response BEFORE refresh (pricing_plans + cmb state)';



COMMENT ON COLUMN public.pricing_refresh_log.after_summary IS 'pricing/summary response AFTER refresh';



COMMENT ON COLUMN public.pricing_refresh_log.diff_count IS 'Total offers changed (new + removed + changed)';



COMMENT ON COLUMN public.pricing_refresh_log.artifacts_path IS 'PVC path containing fetch.log, tier-pricing.csv, summary_*.json';



CREATE SEQUENCE public.pricing_refresh_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.pricing_refresh_log_id_seq OWNED BY public.pricing_refresh_log.id;



CREATE TABLE public.prompt_injection_detections (
    id bigint NOT NULL,
    tenant_id character varying(255) NOT NULL,
    request_id character varying(255) NOT NULL,
    session_key character varying(255),
    detected_at timestamp with time zone DEFAULT now(),
    risk_level integer NOT NULL,
    rule_id integer,
    rule_name character varying(100),
    category character varying(50),
    matched_pattern text,
    input_sample text,
    blocked boolean DEFAULT false,
    action_taken character varying(20) NOT NULL,
    evidence_text text,
    input_hash character varying(64),
    client_ip character varying(45),
    user_agent text,
    CONSTRAINT prompt_injection_detections_risk_level_check CHECK (((risk_level >= 1) AND (risk_level <= 10)))
);



CREATE SEQUENCE public.prompt_injection_detections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.prompt_injection_detections_id_seq OWNED BY public.prompt_injection_detections.id;



CREATE SEQUENCE public.prompt_injection_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.prompt_injection_policies_id_seq OWNED BY public.prompt_injection_policies.id;



CREATE TABLE public.prompt_injection_rules (
    id integer NOT NULL,
    rule_name character varying(100) NOT NULL,
    rule_type character varying(50) NOT NULL,
    category character varying(50) NOT NULL,
    pattern text NOT NULL,
    description text,
    severity integer NOT NULL,
    enabled boolean DEFAULT true,
    case_sensitive boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT prompt_injection_rules_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);



CREATE SEQUENCE public.prompt_injection_rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.prompt_injection_rules_id_seq OWNED BY public.prompt_injection_rules.id;



CREATE VIEW public.prompt_injection_stats_today AS
 SELECT prompt_injection_detections.tenant_id,
    count(*) AS total_detections,
    count(*) FILTER (WHERE (prompt_injection_detections.blocked = true)) AS blocked_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level = 10) OR (prompt_injection_detections.risk_level = 9))) AS critical_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level >= 7) AND (prompt_injection_detections.risk_level <= 8))) AS high_count,
    count(*) FILTER (WHERE ((prompt_injection_detections.risk_level >= 4) AND (prompt_injection_detections.risk_level <= 6))) AS medium_count,
    count(*) FILTER (WHERE (prompt_injection_detections.risk_level <= 3)) AS low_count,
    avg(prompt_injection_detections.risk_level) AS avg_score,
    max(prompt_injection_detections.risk_level) AS max_score
   FROM public.prompt_injection_detections
  WHERE (prompt_injection_detections.detected_at >= CURRENT_DATE)
  GROUP BY prompt_injection_detections.tenant_id;



CREATE TABLE public.provider_catalog (
    code text NOT NULL,
    tier text NOT NULL,
    display_name text NOT NULL,
    display_name_en text,
    category text DEFAULT 'official'::text NOT NULL,
    kind text DEFAULT 'cloud'::text NOT NULL,
    protocol text NOT NULL,
    base_url_template text NOT NULL,
    docs_url text,
    default_egress_profile text DEFAULT 'direct'::text NOT NULL,
    domestic boolean DEFAULT true NOT NULL,
    discount_rate_default numeric(5,4) DEFAULT 1.0,
    models_manifest_json jsonb DEFAULT '[]'::jsonb,
    discovery_strategy text DEFAULT 'auto'::text NOT NULL,
    models_endpoint_template text,
    seed_pricing_plans_json jsonb DEFAULT '[]'::jsonb,
    price_sources_json jsonb DEFAULT '{}'::jsonb,
    hidden boolean DEFAULT false NOT NULL,
    notes text,
    catalog_version integer DEFAULT 1 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    header_profile_code text,
    capabilities jsonb DEFAULT '{}'::jsonb,
    vendor_name text,
    CONSTRAINT provider_catalog_category_check CHECK ((category = ANY (ARRAY['official'::text, 'official_proxy'::text, 'third_party_relay'::text, 'aggregator'::text, 'self_host'::text]))),
    CONSTRAINT provider_catalog_discovery_strategy_check CHECK ((discovery_strategy = ANY (ARRAY['auto'::text, 'manifest'::text, 'hybrid'::text]))),
    CONSTRAINT provider_catalog_kind_check CHECK ((kind = ANY (ARRAY['cloud'::text, 'local'::text]))),
    CONSTRAINT provider_catalog_protocol_check CHECK ((protocol = ANY (ARRAY['openai-completions'::text, 'openai-responses'::text, 'anthropic-messages'::text, 'gemini-generate'::text, 'ollama-native'::text]))),
    CONSTRAINT provider_catalog_tier_check CHECK ((tier = ANY (ARRAY['tier1'::text, 'tier2'::text, 'local'::text, 'restricted'::text])))
);



COMMENT ON COLUMN public.provider_catalog.models_endpoint_template IS '模型清单 API 模板：NULL=自动推导；/models 或 /v1/models 追加到 base_url；https://… 全 URL；空串=仅 manifest';



COMMENT ON COLUMN public.provider_catalog.capabilities IS 'Per-catalog capability flags and request sanitization config';



COMMENT ON COLUMN public.provider_catalog.vendor_name IS 'Human-readable vendor name for grouped view, e.g. "OpenAI", "Anthropic", "DeepSeek"';




CREATE TABLE public.provider_events (
    id bigint,
    credential_id bigint,
    event_kind text,
    payload_json jsonb,
    ts timestamp with time zone
);




CREATE TABLE public.provider_header_profiles (
    id bigint NOT NULL,
    profile_code text NOT NULL,
    display_name text NOT NULL,
    protocol text,
    headers_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    strip_headers_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);



CREATE SEQUENCE public.provider_header_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.provider_header_profiles_id_seq OWNED BY public.provider_header_profiles.id;



CREATE SEQUENCE public.provider_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.provider_models_id_seq OWNED BY public.provider_models.id;



CREATE TABLE public.provider_quality_rollup (
    provider_id integer NOT NULL,
    bucket_start timestamp with time zone NOT NULL,
    total_requests integer DEFAULT 0 NOT NULL,
    bad_requests integer DEFAULT 0 NOT NULL,
    fixed_requests integer DEFAULT 0 NOT NULL,
    avg_quality_score numeric(3,2),
    top_flag text
);



CREATE TABLE public.provider_scores (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    score numeric(6,4) NOT NULL,
    factors_json jsonb,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);



CREATE SEQUENCE public.provider_scores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.provider_scores_id_seq OWNED BY public.provider_scores.id;



CREATE TABLE public.provider_settings (
    id bigint NOT NULL,
    provider_id bigint NOT NULL,
    setting_key text NOT NULL,
    setting_value jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_by text DEFAULT 'system'::text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);



COMMENT ON TABLE public.provider_settings IS 'Provider级别的配置覆盖，优先级高于平台默认配置';



COMMENT ON COLUMN public.provider_settings.setting_key IS '配置键，如: compression.mode, cache.enabled, format_conversion.enabled';



COMMENT ON COLUMN public.provider_settings.setting_value IS '配置值，JSON格式，如: "off", true, false';



COMMENT ON COLUMN public.provider_settings.enabled IS '是否启用该配置覆盖';



CREATE SEQUENCE public.provider_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.provider_settings_id_seq OWNED BY public.provider_settings.id;



CREATE TABLE public.providers (
    id bigint NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    code text NOT NULL,
    display_name text NOT NULL,
    catalog_code text,
    is_custom boolean DEFAULT false NOT NULL,
    catalog_version_at_create integer,
    user_overrides_json jsonb DEFAULT '[]'::jsonb NOT NULL,
    kind text DEFAULT 'cloud'::text NOT NULL,
    category text DEFAULT 'official'::text NOT NULL,
    protocol text NOT NULL,
    base_url text NOT NULL,
    egress_profile text DEFAULT 'direct'::text NOT NULL,
    domestic boolean DEFAULT true NOT NULL,
    discount_rate numeric(5,4) DEFAULT 1.0,
    enabled boolean DEFAULT true NOT NULL,
    network_quality_score numeric(4,3) DEFAULT 1.000,
    owner_user text,
    notes text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    manual_disabled boolean DEFAULT false NOT NULL,
    quality_fix_mode text DEFAULT 'off'::text NOT NULL,
    CONSTRAINT providers_category_check CHECK ((category = ANY (ARRAY['official'::text, 'official_proxy'::text, 'third_party_relay'::text, 'aggregator'::text, 'self_host'::text]))),
    CONSTRAINT providers_kind_check CHECK ((kind = ANY (ARRAY['cloud'::text, 'local'::text]))),
    CONSTRAINT providers_quality_fix_mode_check CHECK ((quality_fix_mode = ANY (ARRAY['off'::text, 'detect_only'::text, 'fix'::text])))
);



COMMENT ON COLUMN public.providers.quality_fix_mode IS 'off         : passthrough, no detection, no rewrite.
     detect_only : detect tool_call quality issues, write request_log signals,
                   but do NOT modify the response body sent to the client.
     fix         : detect + write signals + rewrite the response body
                   (rename empty names, dedup ids, etc.) before forwarding.';



CREATE SEQUENCE public.providers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.providers_id_seq OWNED BY public.providers.id;



CREATE TABLE public.request_envelope (
    request_id uuid NOT NULL,
    client_model text NOT NULL,
    client_metadata jsonb,
    client_headers_redacted jsonb,
    outbound_model text,
    outbound_protocol text,
    credential_id bigint,
    fingerprint_seed text,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    stream_completed boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL
);



CREATE TABLE public.request_logs_2026_06 (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    upstream_status_code integer,
    test_col text[] DEFAULT '{}'::text[] NOT NULL,
    test_tab_indent text,
    provider_model text,
    has_attachments boolean DEFAULT false,
    attachment_count integer DEFAULT 0,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);



CREATE TABLE public.request_logs_2026_07 (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    upstream_status_code integer,
    test_col text[] DEFAULT '{}'::text[] NOT NULL,
    test_tab_indent text,
    provider_model text,
    has_attachments boolean DEFAULT false,
    attachment_count integer DEFAULT 0,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);



COMMENT ON COLUMN public.request_logs_2026_07.cost_display IS 'Request-level displayed cost in its native currency; may differ from cost_usd when provider pricing is not USD.';



COMMENT ON COLUMN public.request_logs_2026_07.cost_currency IS 'Currency for request_logs.cost_display, e.g. USD/CNY.';



COMMENT ON COLUMN public.request_logs_2026_07.is_auto_request IS 'Auto route: was this request model=auto?';



COMMENT ON COLUMN public.request_logs_2026_07.task_type IS 'Auto route: classified task type (chat/reasoning/code/...)';



COMMENT ON COLUMN public.request_logs_2026_07.auto_profile IS 'Auto route: profile used (smart/speed_first/cost_first)';



COMMENT ON COLUMN public.request_logs_2026_07.auto_decision IS 'Auto route: top-N candidates + chosen model + scoring breakdown';



COMMENT ON COLUMN public.request_logs_2026_07.auto_confidence IS 'Auto route: classification confidence 0-1';



COMMENT ON COLUMN public.request_logs_2026_07.parent_request_id IS 'Round 47 (2026-06-18): the pre-compression request_id when compressor rewrote the body. NULL for uncompressed rows. Single-level chain only (child has at most 1 parent).';



COMMENT ON COLUMN public.request_logs_2026_07.compression_reason IS 'Round 47 (2026-06-18): why compression fired. mode_1_auto_threshold = body > cand.ContextWindow × 0.8 × 3.5 (LLM_GATEWAY_COMPRESSION_MODE=1). mode_2_on_4xx = upstream 4xx context_length_exceeded (LLM_GATEWAY_COMPRESSION_MODE=2). NULL = no compression event, OR pre-request trim happened without 4xx (T-NEW-4). See compression_meta.trim_phase for explicit phase tagging.';



COMMENT ON COLUMN public.request_logs_2026_07.compression_strategy IS 'Round 47 (2026-06-18): which decompression path succeeded. mechanical_trim = oldest-pair drop (transform/ctx_compress.go). memora_l1_inject = dynamic_context user message from Memora /product/search. llm_summary = 1M-context model summary. noop = attempted but skipped (e.g. warmup_min_facts guard).';



COMMENT ON COLUMN public.request_logs_2026_07.compression_meta IS 'Round 47 (2026-06-18): compression telemetry. 4xx recovery fields (T-NEW-2): tokens_before/after, bytes_before/after, context_window_used, threshold_bytes, dropped_messages, summary_chars, model_used, latency_ms, memora_facts_used, warmup_skipped, first_user_retained, system_retained, reason_detail. Pre-request trim fields (T-NEW-4): trim_phase="pre_request", phases=["pre_request_trim"] or ["pre_request_trim","4xx_recovery"], reason_detail="pre-request trim (cand.ContextWindow × 0.85 × 3.5 threshold)". See v7 §3.2.';



COMMENT ON COLUMN public.request_logs_2026_07.outbound_body IS 'v3 (2026-06-19): LLM wire body JSONB — what was actually forwarded to the
     upstream provider. NULL = no session compressor active (outbound == client).
     Differs from request_body when v3 session-level delta-append or proactive
     sliding-window summary rewrote the body before forwarding.';



COMMENT ON COLUMN public.request_logs_2026_07.outbound_msg_count IS 'v3 (2026-06-19): Message count inside outbound_body (including system).
     Compare to the client message count in request_body to measure delta.';



COMMENT ON COLUMN public.request_logs_2026_07.outbound_token_est IS 'v3 (2026-06-19): Estimated token count for outbound_body using the
     3.5 chars/token heuristic (same as compressor/estimator.go). Used to
     audit sliding-window threshold decisions in request_logs UI.';



COMMENT ON COLUMN public.request_logs_2026_07.outbound_msg_hashes IS 'v3 (2026-06-19): Per-message fingerprint array [{index, sha256}] for
     outbound_body messages. The next request with the same gw_session_id
     reads this column to run LCS diff and find the incremental message tail,
     enabling delta-append without full re-send of conversation history.';



COMMENT ON COLUMN public.request_logs_2026_07.upstream_finish_reason IS '2026-06-19 T-NEW-7: the SOLE home for the upstream finish_reason
     (stop, tool_calls, length, end_turn, function_call, max_tokens, …).
     NULL means the stream ended without a finish_reason (e.g. truncated
     pre-finish).  Populated for BOTH success and failure rows.
     This column REPLACES the prior use of failure_detail_code for
     finish reasons; see the migration header for the full rationale.';



COMMENT ON COLUMN public.request_logs_2026_07.tool_calls IS 'Structured tool calls from assistant message. OpenAI format: [{id, type, function: {name, arguments}}]. Populated for both streaming and non-streaming responses.';



COMMENT ON COLUMN public.request_logs_2026_07.upstream_status_code IS 'HTTP status code returned by upstream (NULL = network-level error, success, or unknown). Populated from the last attempt in executor.go and persisted via telemetry/client.go INSERT/UPDATE.';




CREATE TABLE public.request_logs_2026_07_columnar_backup (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    upstream_status_code integer,
    test_col text[] DEFAULT '{}'::text[] NOT NULL,
    test_tab_indent text,
    provider_model text,
    has_attachments boolean DEFAULT false,
    attachment_count integer DEFAULT 0,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);




CREATE TABLE public.request_logs_2026_08 (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    upstream_status_code integer,
    test_col text[] DEFAULT '{}'::text[] NOT NULL,
    test_tab_indent text,
    provider_model text,
    has_attachments boolean DEFAULT false,
    attachment_count integer DEFAULT 0,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);



CREATE TABLE public.request_logs_archive (
    id bigint NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    stream_chunk_errors integer,
    stream_done_sent boolean,
    client_timeout boolean,
    client_endpoint text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    stream_interrupted boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    client_request_id text,
    provider_model text,
    CONSTRAINT chk_archive_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_archive_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
)
PARTITION BY RANGE (ts);




CREATE TABLE public.request_logs_archive_2026_08 (
    id bigint NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    stream_chunk_errors integer,
    stream_done_sent boolean,
    client_timeout boolean,
    client_endpoint text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    stream_interrupted boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    client_request_id text,
    provider_model text,
    CONSTRAINT chk_archive_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_archive_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);




CREATE TABLE public.request_logs_default (
    id bigint DEFAULT nextval('public.request_logs_id_seq'::regclass) NOT NULL,
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    client_model text,
    outbound_model text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    client_profile text,
    request_mode text,
    prompt_tokens integer,
    completion_tokens integer,
    total_tokens integer,
    cost_usd numeric(14,8),
    latency_ms integer,
    success boolean NOT NULL,
    error_kind text,
    search_text text,
    cache_read_tokens integer,
    cache_write_tokens integer,
    identity_hash text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    affinity_hit boolean,
    stream_first_chunk_ms integer,
    stream_chunk_count integer,
    stream_interrupted boolean,
    stream_done_sent boolean,
    request_checksum text,
    response_checksum text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    request_preview text,
    transform_summary text,
    response_preview text,
    stream_done_received boolean,
    request_body jsonb,
    response_body jsonb,
    cost_display numeric(14,8),
    cost_currency text,
    usage_source text DEFAULT 'llm'::text NOT NULL,
    gw_session_id text,
    gw_task_id text,
    request_status text,
    api_key_prefix text,
    owner_user text,
    application_code text,
    key_alias text,
    api_key_owner_user text,
    is_auto_request boolean DEFAULT false,
    task_type text,
    auto_profile text,
    auto_decision jsonb,
    auto_confidence numeric(4,3),
    work_type text,
    task_type_chosen text,
    confidence_num numeric(4,3),
    model_chosen text,
    strategy_used text,
    credits_charged bigint,
    parent_request_id text,
    compression_reason text,
    compression_strategy text,
    compression_meta jsonb,
    outbound_body jsonb,
    outbound_msg_count integer,
    outbound_token_est integer,
    outbound_msg_hashes jsonb,
    quality_flags text[] DEFAULT '{}'::text[] NOT NULL,
    quality_fix_actions jsonb DEFAULT '{}'::jsonb NOT NULL,
    quality_score numeric(3,2),
    upstream_finish_reason text,
    tool_calls jsonb,
    client_endpoint text,
    client_timeout boolean,
    stream_chunk_errors integer,
    stream_chunks_sent integer DEFAULT 0 NOT NULL,
    client_request_id text,
    upstream_status_code integer,
    test_col text[] DEFAULT '{}'::text[] NOT NULL,
    test_tab_indent text,
    provider_model text,
    has_attachments boolean DEFAULT false,
    attachment_count integer DEFAULT 0,
    CONSTRAINT chk_compression_parent_single CHECK (((parent_request_id IS NULL) OR (compression_reason IS NOT NULL))),
    CONSTRAINT request_logs_strategy_used_check CHECK (((strategy_used IS NULL) OR (strategy_used = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text]))))
);



CREATE TABLE public.request_wal (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
)
PARTITION BY RANGE (created_at);



COMMENT ON TABLE public.request_wal IS 'Request WAL: synchronous initial log + async batch updates for request lifecycle';




CREATE TABLE public.request_wal_2026_06 (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
);




CREATE TABLE public.request_wal_2026_07 (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
);




CREATE TABLE public.request_wal_2026_07_columnar (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
);




CREATE TABLE public.request_wal_2026_08 (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
);



CREATE TABLE public.request_wal_bodies (
    request_id character varying(64) NOT NULL,
    outbound_body text,
    compression_meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);



COMMENT ON TABLE public.request_wal_bodies IS 'Large outbound bodies separated for performance';



CREATE TABLE public.request_wal_default (
    request_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    gw_session_id character varying(128),
    status character varying(20) DEFAULT 'pending'::character varying NOT NULL,
    stage smallint DEFAULT 0 NOT NULL,
    client_model character varying(100),
    upstream_provider_id bigint,
    upstream_credential_id bigint,
    completion_tokens integer,
    prompt_tokens integer,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    completed_at timestamp with time zone,
    upstream_request_at timestamp with time zone,
    upstream_response_at timestamp with time zone,
    error text,
    compression_strategy character varying(50),
    compression_meta jsonb
);



CREATE TABLE public.response_format_anomalies (
    id bigint NOT NULL,
    detected_at timestamp with time zone DEFAULT now() NOT NULL,
    request_id text NOT NULL,
    provider_id integer,
    provider_code text,
    client_model text,
    outbound_model text,
    anomaly_type text NOT NULL,
    severity text DEFAULT 'medium'::text NOT NULL,
    usage_source text,
    expected_tokens integer,
    actual_tokens integer,
    content_size_bytes integer,
    response_structure jsonb,
    response_sample text,
    resolved boolean DEFAULT false NOT NULL,
    resolved_at timestamp with time zone,
    resolution_notes text,
    tenant_id text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);



CREATE SEQUENCE public.response_format_anomalies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.response_format_anomalies_id_seq OWNED BY public.response_format_anomalies.id;



CREATE TABLE public.route_decisions (
    id bigint NOT NULL,
    request_id text,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    tenant_id text,
    api_key_id bigint,
    canonical_id bigint,
    selected_credential_id bigint,
    candidates_json jsonb,
    reason text,
    sticky_hit boolean
);



CREATE SEQUENCE public.route_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.route_decisions_id_seq OWNED BY public.route_decisions.id;



CREATE TABLE public.routing_audit_log (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now(),
    actor text NOT NULL,
    action text NOT NULL,
    target_type text,
    target_id bigint,
    before_json jsonb,
    after_json jsonb
);



CREATE SEQUENCE public.routing_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.routing_audit_log_id_seq OWNED BY public.routing_audit_log.id;



CREATE TABLE public.routing_decision_log (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
)
PARTITION BY RANGE (ts);



COMMENT ON TABLE public.routing_decision_log IS 'Routing decision logs - partitioned by month (RANGE on ts). Current month uses heap storage. Historical months are archived to routing_decision_log_archive (columnar) via archive_routing_decision_log() function. Call this monthly on day 1.';



CREATE TABLE public.routing_decision_log_2026_07 (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
);



CREATE TABLE public.routing_decision_log_2026_08 (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
);



CREATE TABLE public.routing_decision_log_archive (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
)
PARTITION BY RANGE (ts);




CREATE TABLE public.routing_decision_log_archive_2026_08 (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
);




CREATE TABLE public.routing_decision_log_default (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
);



CREATE TABLE public.routing_decision_log_old (
    ts timestamp with time zone DEFAULT now() NOT NULL,
    request_id uuid NOT NULL,
    idempotency_key text,
    tenant_id text,
    api_key_id bigint,
    model text NOT NULL,
    chosen_credential_id bigint,
    chosen_provider_id bigint,
    tier smallint,
    candidates_tried smallint,
    latency_ms integer,
    success boolean NOT NULL,
    error_class text,
    prompt_tokens integer,
    completion_tokens integer,
    cost_usd numeric(12,6),
    request_bytes integer,
    response_bytes integer,
    client_model text,
    resolved_raw_model text,
    sticky_hit boolean,
    client_profile text,
    outbound_model text,
    request_mode text,
    identity_hash text,
    transform_rule_id text,
    egress_protocol text,
    failure_stage text,
    failure_detail_code text,
    virtual_client_id text,
    virtual_ip text,
    virtual_mac text,
    resolution_path text,
    canonical_model text,
    resolution_raw_models jsonb,
    decision_trace jsonb
);



COMMENT ON TABLE public.routing_decision_log_old IS 'DEPRECATED: Old non-partitioned routing_decision_log table. Verify routing_decision_log works correctly, then DROP TABLE routing_decision_log_old;';



CREATE TABLE public.routing_overrides (
    id bigint NOT NULL,
    task_type text NOT NULL,
    profile text DEFAULT ''::text NOT NULL,
    mode text NOT NULL,
    model_chosen text,
    reason text DEFAULT ''::text NOT NULL,
    created_by text,
    expires_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT routing_overrides_mode_check CHECK ((mode = ANY (ARRAY['pin'::text, 'ban'::text])))
);



CREATE TABLE public.routing_overrides_audit (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    action text NOT NULL,
    override_id bigint,
    task_type text,
    profile text,
    mode text,
    model_chosen text,
    reason text,
    expires_at timestamp with time zone,
    old_expires_at timestamp with time zone,
    actor text,
    CONSTRAINT routing_overrides_audit_action_check CHECK ((action = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text])))
);



CREATE SEQUENCE public.routing_overrides_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.routing_overrides_audit_id_seq OWNED BY public.routing_overrides_audit.id;



CREATE SEQUENCE public.routing_overrides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.routing_overrides_id_seq OWNED BY public.routing_overrides.id;



CREATE TABLE public.routing_policy (
    id smallint DEFAULT 1 NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    weights_json jsonb DEFAULT '{}'::jsonb NOT NULL,
    sticky_ttl_seconds integer DEFAULT 1800 NOT NULL,
    local_bonus numeric(4,3) DEFAULT 0.000 NOT NULL,
    notes text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    algorithm_version smallint DEFAULT 2,
    retry_per_credential smallint DEFAULT 1,
    tier_fallback_max smallint DEFAULT 4,
    slot_soft_limit_ratio numeric(3,2) DEFAULT 1.00,
    slot_hard_limit_ratio numeric(3,2) DEFAULT 1.50,
    slot_wait_max_ms smallint DEFAULT 200,
    circuit_open_seconds integer DEFAULT 300,
    circuit_failure_threshold smallint DEFAULT 5,
    circuit_max_open_seconds integer DEFAULT 1800,
    featured_models text[] DEFAULT ARRAY['gpt-4o'::text, 'gpt-4o-mini'::text, 'claude-3-5-sonnet-20241022'::text, 'claude-3-7-sonnet-20250219'::text, 'gemini-2.0-flash'::text, 'gemini-1.5-pro'::text, 'deepseek-chat'::text, 'qwen-plus'::text],
    transient_fail_threshold integer DEFAULT 2 NOT NULL,
    stats_window_minutes integer DEFAULT 10,
    stats_update_interval_seconds integer DEFAULT 60,
    scoring_weights_json jsonb DEFAULT '{"price": 10, "session_load": 5, "failure_penalty": 20, "default_price_cny": 5.0, "default_price_usd": 5.0}'::jsonb,
    CONSTRAINT routing_policy_id_check CHECK ((id = 1)),
    CONSTRAINT routing_policy_transient_fail_threshold_check CHECK (((transient_fail_threshold >= 0) AND (transient_fail_threshold <= 10)))
);



CREATE TABLE public.schema_migration_audit (
    migration_id text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    row_count bigint DEFAULT 0 NOT NULL,
    note text DEFAULT ''::text NOT NULL
);



CREATE TABLE public.schema_migrations (
    version text NOT NULL,
    description text,
    applied_at timestamp with time zone DEFAULT now()
);



CREATE TABLE public.security_audit_log (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    event_kind text NOT NULL,
    api_key_id bigint,
    internal_service_id text,
    actor text,
    tenant_id text,
    remote_ip inet,
    detail_json jsonb,
    CONSTRAINT security_audit_log_event_kind_check CHECK ((event_kind = ANY (ARRAY['key_created'::text, 'key_disabled'::text, 'key_throttled'::text, 'key_unthrottled'::text, 'key_revoked'::text, 'key_revealed'::text, 'auth_failed'::text, 'auth_expired'::text, 'admin_login_failed'::text, 'key_reencrypted'::text, 'hmac_sig_failed'::text, 'hmac_nonce_replay'::text, 'hmac_timestamp_bad'::text, 'rate_limited'::text, 'anomaly_spike'::text])))
);



CREATE SEQUENCE public.security_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.security_audit_log_id_seq OWNED BY public.security_audit_log.id;



CREATE TABLE public.session_audit_records (
    id bigint NOT NULL,
    session_id text NOT NULL,
    tenant_id text NOT NULL,
    request_id text NOT NULL,
    client_ip text,
    client_user_agent text,
    client_model text,
    content_summary text,
    content_title text,
    content_hash text,
    intent_type text,
    intent_score double precision,
    intent_reason text,
    security_score integer,
    danger_score integer,
    trust_score integer,
    sensitive_score integer,
    detect_score integer DEFAULT 0 NOT NULL,
    detect_decision text DEFAULT 'pass'::text NOT NULL,
    threats jsonb DEFAULT '[]'::jsonb NOT NULL,
    sensitive_words jsonb DEFAULT '[]'::jsonb NOT NULL,
    status text DEFAULT 'pass'::text NOT NULL,
    approval_status text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.session_audit_records FORCE ROW LEVEL SECURITY;



CREATE SEQUENCE public.session_audit_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.session_audit_records_id_seq OWNED BY public.session_audit_records.id;



CREATE TABLE public.session_memora_extraction_log (
    task_id text NOT NULL,
    extracted_at timestamp with time zone DEFAULT now() NOT NULL,
    written integer DEFAULT 0 NOT NULL,
    skipped_noise integer DEFAULT 0 NOT NULL,
    skipped_duplicate integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'ok'::text NOT NULL,
    detail jsonb
);



CREATE TABLE public.session_summaries (
    session_key character varying(255) NOT NULL,
    tenant_id character varying(255) NOT NULL,
    first_request_at timestamp with time zone NOT NULL,
    last_request_at timestamp with time zone NOT NULL,
    duration_seconds integer GENERATED ALWAYS AS ((EXTRACT(epoch FROM (last_request_at - first_request_at)))::integer) STORED,
    request_count integer DEFAULT 0 NOT NULL,
    success_count integer DEFAULT 0 NOT NULL,
    error_count integer DEFAULT 0 NOT NULL,
    total_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    input_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    output_cost_usd numeric(12,6) DEFAULT 0 NOT NULL,
    total_prompt_tokens bigint DEFAULT 0 NOT NULL,
    total_completion_tokens bigint DEFAULT 0 NOT NULL,
    total_tokens bigint GENERATED ALWAYS AS ((total_prompt_tokens + total_completion_tokens)) STORED,
    avg_latency_ms integer DEFAULT 0 NOT NULL,
    min_latency_ms integer,
    max_latency_ms integer,
    models_used text[] DEFAULT '{}'::text[] NOT NULL,
    primary_model character varying(100),
    model_switch_count integer DEFAULT 0 NOT NULL,
    title character varying(200),
    summary text,
    key_topics text[],
    user_intent character varying(50),
    quality_score integer,
    compliance_status character varying(20) DEFAULT 'compliant'::character varying,
    compliance_issues_count integer DEFAULT 0 NOT NULL,
    prompt_injection_detected boolean DEFAULT false,
    pii_detected boolean DEFAULT false,
    toxic_output_detected boolean DEFAULT false,
    work_types text[],
    providers text[],
    client_models text[],
    last_summarized_at timestamp with time zone,
    summary_version integer DEFAULT 1,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT session_summaries_quality_score_check CHECK (((quality_score >= 0) AND (quality_score <= 10)))
);



CREATE VIEW public.session_stats_today AS
 SELECT session_summaries.tenant_id,
    count(*) AS session_count,
    count(*) FILTER (WHERE (session_summaries.last_request_at > (now() - '01:00:00'::interval))) AS active_sessions,
    sum(session_summaries.request_count) AS total_requests,
    sum(session_summaries.total_cost_usd) AS total_cost,
    avg(session_summaries.total_cost_usd) AS avg_cost_per_session,
    avg(session_summaries.total_tokens) AS avg_tokens_per_session,
    avg(session_summaries.avg_latency_ms) AS avg_latency,
    (((count(*) FILTER (WHERE ((session_summaries.compliance_status)::text = 'compliant'::text)))::numeric * 100.0) / (NULLIF(count(*), 0))::numeric) AS compliance_rate,
    (((count(*) FILTER (WHERE (session_summaries.quality_score >= 8)))::numeric * 100.0) / (NULLIF(count(*) FILTER (WHERE (session_summaries.quality_score IS NOT NULL)), 0))::numeric) AS high_quality_rate
   FROM public.session_summaries
  WHERE (session_summaries.first_request_at >= CURRENT_DATE)
  GROUP BY session_summaries.tenant_id;



CREATE TABLE public.session_titles (
    task_id text NOT NULL,
    scoped_session_id text DEFAULT ''::text NOT NULL,
    title text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    model text,
    api_key_id integer
);



CREATE TABLE public.settings_audit (
    id bigint NOT NULL,
    setting_key character varying(128) NOT NULL,
    tenant_id character varying(64),
    action character varying(16) NOT NULL,
    old_value jsonb,
    new_value jsonb,
    operator_user character varying(64) NOT NULL,
    operator_role character varying(32) NOT NULL,
    confirm_token character varying(64),
    client_ip character varying(45),
    created_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.settings_audit FORCE ROW LEVEL SECURITY;



COMMENT ON TABLE public.settings_audit IS '设置修改审计日志（bg/settings_audit_cleaner.go 每 24h 清理 7 天前的数据）';



COMMENT ON COLUMN public.settings_audit.action IS 'update / rollback / delete';



CREATE SEQUENCE public.settings_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.settings_audit_id_seq OWNED BY public.settings_audit.id;



CREATE TABLE public.settings_kv (
    key character varying(128) NOT NULL,
    value jsonb NOT NULL,
    value_type character varying(32) NOT NULL,
    scope character varying(16) DEFAULT 'platform'::character varying NOT NULL,
    category character varying(32) DEFAULT 'general'::character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by character varying(64),
    prev_value jsonb,
    prev_updated_at timestamp with time zone
);



COMMENT ON TABLE public.settings_kv IS '平台级运行时设置（Q2: 立即生效）';



COMMENT ON COLUMN public.settings_kv.prev_value IS '上次的值，用于一键回滚';



CREATE TABLE public.sticky_sessions (
    sticky_key text NOT NULL,
    credential_id bigint NOT NULL,
    set_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    canonical_id bigint,
    last_request_id text
);



CREATE TABLE public.subscription_plans (
    id integer NOT NULL,
    code character varying(32) NOT NULL,
    tier character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    price_cents integer NOT NULL,
    monthly_credits bigint NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT subscription_plans_tier_check CHECK (((tier)::text = ANY (ARRAY[('basic'::character varying)::text, ('pro'::character varying)::text, ('max'::character varying)::text])))
);



CREATE SEQUENCE public.subscription_plans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.subscription_plans_id_seq OWNED BY public.subscription_plans.id;



CREATE TABLE public.system_identity_pool (
    id integer DEFAULT 1 NOT NULL,
    max_identities integer DEFAULT 10000 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    CONSTRAINT system_identity_pool_id_check CHECK ((id = 1))
);



COMMENT ON TABLE public.system_identity_pool IS 'Global cap on total distinct end-user identities the gateway will accept. Once this many unique fingerprints are active, new connections must reuse an existing fingerprint (round-robin among least-recently-used).';



CREATE TABLE public.tenant_credit_wallets (
    tenant_id character varying(64) NOT NULL,
    balance_credits bigint DEFAULT 0 NOT NULL,
    locked_credits bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    granted_balance bigint DEFAULT 0 NOT NULL,
    purchased_balance bigint DEFAULT 0 NOT NULL
);



CREATE TABLE public.tenant_model_policies (
    id bigint NOT NULL,
    tenant_id character varying(64) NOT NULL,
    canonical_name text NOT NULL,
    reason text DEFAULT ''::text NOT NULL,
    created_by character varying(128) DEFAULT ''::character varying NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by character varying(128),
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenant_model_policies_canonical_name_check CHECK ((canonical_name <> ''::text))
);

ALTER TABLE ONLY public.tenant_model_policies FORCE ROW LEVEL SECURITY;



CREATE VIEW public.tenant_model_policies_active AS
 SELECT tenant_model_policies.id,
    tenant_model_policies.tenant_id,
    tenant_model_policies.canonical_name,
    tenant_model_policies.reason,
    tenant_model_policies.created_by,
    tenant_model_policies.created_at,
    tenant_model_policies.updated_at
   FROM public.tenant_model_policies
  WHERE (tenant_model_policies.deleted_at IS NULL);



CREATE TABLE public.tenant_model_policies_audit (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    action text NOT NULL,
    policy_id bigint,
    tenant_id text,
    canonical_name text,
    reason text,
    actor text,
    CONSTRAINT tenant_model_policies_audit_action_check CHECK ((action = ANY (ARRAY['insert'::text, 'update'::text, 'delete'::text, 'undelete'::text])))
);

ALTER TABLE ONLY public.tenant_model_policies_audit FORCE ROW LEVEL SECURITY;



CREATE SEQUENCE public.tenant_model_policies_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tenant_model_policies_audit_id_seq OWNED BY public.tenant_model_policies_audit.id;



CREATE SEQUENCE public.tenant_model_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tenant_model_policies_id_seq OWNED BY public.tenant_model_policies.id;



CREATE TABLE public.tenant_settings_kv (
    tenant_id character varying(64) NOT NULL,
    key character varying(128) NOT NULL,
    value jsonb NOT NULL,
    value_type character varying(32) NOT NULL,
    category character varying(32) DEFAULT 'general'::character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by character varying(64),
    prev_value jsonb,
    prev_updated_at timestamp with time zone
);

ALTER TABLE ONLY public.tenant_settings_kv FORCE ROW LEVEL SECURITY;



COMMENT ON TABLE public.tenant_settings_kv IS '租户级运行时设置（Q3）';



CREATE TABLE public.tenant_subscriptions (
    id integer NOT NULL,
    tenant_id character varying(64) NOT NULL,
    plan_id integer NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    period_start timestamp with time zone NOT NULL,
    period_end timestamp with time zone NOT NULL,
    quota_remaining bigint DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenant_subscriptions_status_check CHECK (((status)::text = ANY (ARRAY[('pending'::character varying)::text, ('active'::character varying)::text, ('expired'::character varying)::text, ('cancelled'::character varying)::text])))
);



CREATE SEQUENCE public.tenant_subscriptions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tenant_subscriptions_id_seq OWNED BY public.tenant_subscriptions.id;



CREATE TABLE public.tenant_tool_policies (
    id bigint NOT NULL,
    tenant_id character varying(64) NOT NULL,
    tool_pattern character varying(128) NOT NULL,
    policy_type character varying(16) NOT NULL,
    reason character varying(256),
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    created_by character varying(128),
    CONSTRAINT chk_policy_type CHECK (((policy_type)::text = ANY (ARRAY[('allow'::character varying)::text, ('deny'::character varying)::text])))
);

ALTER TABLE ONLY public.tenant_tool_policies FORCE ROW LEVEL SECURITY;



COMMENT ON TABLE public.tenant_tool_policies IS 'Tenant-level tool access policies (Phase 3.4: 权限控制)';



COMMENT ON COLUMN public.tenant_tool_policies.tool_pattern IS 'Tool pattern: exact match (filesystem.read_file) or wildcard (filesystem.*)';



COMMENT ON COLUMN public.tenant_tool_policies.policy_type IS 'Policy type: allow (whitelist) or deny (blacklist)';



COMMENT ON COLUMN public.tenant_tool_policies.reason IS 'Reason for this policy (audit trail)';



CREATE SEQUENCE public.tenant_tool_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tenant_tool_policies_id_seq OWNED BY public.tenant_tool_policies.id;



CREATE TABLE public.tenants (
    code character varying(64) NOT NULL,
    name character varying(128) NOT NULL,
    status character varying(32) DEFAULT 'active'::character varying NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    contact_email character varying(256) DEFAULT ''::character varying NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tenants_status_check CHECK (((status)::text = ANY (ARRAY[('active'::character varying)::text, ('trial'::character varying)::text, ('suspended'::character varying)::text, ('expired'::character varying)::text, ('disabled'::character varying)::text])))
);




CREATE TABLE public.test_columnar_new (
    id integer NOT NULL,
    tenant_id text,
    model text,
    prompt_tokens integer,
    completion_tokens integer,
    created_at timestamp with time zone DEFAULT now()
);




CREATE TABLE public.token_audit_events (
    id bigint NOT NULL,
    request_id text NOT NULL,
    credential_id bigint NOT NULL,
    claimed_tokens integer,
    estimated_tokens integer,
    delta_pct numeric(6,3),
    ts timestamp with time zone DEFAULT now() NOT NULL
);



CREATE SEQUENCE public.token_audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.token_audit_events_id_seq OWNED BY public.token_audit_events.id;




CREATE TABLE public.tool_call_events (
    id bigint,
    tool_id character varying(128),
    tenant_id character varying(64),
    request_id character varying(64),
    api_key character varying(64),
    status character varying(16),
    latency_ms integer,
    error_code character varying(64),
    called_at timestamp with time zone
);




CREATE TABLE public.tool_categories (
    id character varying(64) NOT NULL,
    name character varying(128) NOT NULL,
    description text,
    enabled boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);



COMMENT ON TABLE public.tool_categories IS 'Phase 2: Tool category definitions for layered loading';



CREATE TABLE public.tool_registry (
    id integer NOT NULL,
    category character varying(64) NOT NULL,
    tool_name character varying(128) NOT NULL,
    tool_definition jsonb NOT NULL,
    enabled boolean DEFAULT true,
    priority integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    tool_id character varying(128) NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying,
    version integer DEFAULT 1,
    deprecation_date timestamp with time zone,
    min_client_version character varying(32),
    breaking_changes jsonb DEFAULT '[]'::jsonb,
    superseded_by character varying(128)
);



COMMENT ON TABLE public.tool_registry IS 'Phase 2: Centralized tool definition registry';



COMMENT ON COLUMN public.tool_registry.tool_id IS 'Phase 3: Unique tool identifier (category.tool_name)';



COMMENT ON COLUMN public.tool_registry.tenant_id IS 'Phase 3: Tenant isolation (default = global shared)';



COMMENT ON COLUMN public.tool_registry.version IS 'Tool version (Phase 3.2: 多版本共存)';



COMMENT ON COLUMN public.tool_registry.deprecation_date IS 'Deprecated after this date (Phase 3.2: 版本管理)';



COMMENT ON COLUMN public.tool_registry.min_client_version IS 'Minimum client version required (Phase 3.2: 版本管理)';



COMMENT ON COLUMN public.tool_registry.breaking_changes IS 'List of breaking changes in this version (Phase 3.2: 版本管理)';



COMMENT ON COLUMN public.tool_registry.superseded_by IS 'Newer tool_id that replaces this version (Phase 3.2: 版本管理)';



CREATE SEQUENCE public.tool_registry_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tool_registry_id_seq OWNED BY public.tool_registry.id;



CREATE TABLE public.tool_usage_stats (
    id bigint NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
)
PARTITION BY RANGE (created_at);



CREATE SEQUENCE public.tool_usage_stats_partitioned_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tool_usage_stats_partitioned_id_seq OWNED BY public.tool_usage_stats.id;



CREATE TABLE public.tool_usage_stats_2026_06 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);



CREATE TABLE public.tool_usage_stats_2026_07 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);



CREATE TABLE public.tool_usage_stats_2026_08 (
    id bigint DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass) NOT NULL,
    tool_id character varying NOT NULL,
    tenant_id character varying NOT NULL,
    usage_date date NOT NULL,
    call_count bigint DEFAULT 0,
    success_count bigint DEFAULT 0,
    error_count bigint DEFAULT 0,
    avg_latency_ms integer,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone
);



CREATE TABLE public.tool_usage_stats_old (
    id bigint NOT NULL,
    tool_id character varying(128) NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying NOT NULL,
    usage_date date DEFAULT CURRENT_DATE NOT NULL,
    call_count bigint DEFAULT 0 NOT NULL,
    success_count bigint DEFAULT 0 NOT NULL,
    error_count bigint DEFAULT 0 NOT NULL,
    avg_latency_ms integer DEFAULT 0,
    last_called_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);

ALTER TABLE ONLY public.tool_usage_stats_old FORCE ROW LEVEL SECURITY;



COMMENT ON TABLE public.tool_usage_stats_old IS 'Tool usage statistics (Phase 3.3: 使用统计)';



COMMENT ON COLUMN public.tool_usage_stats_old.call_count IS 'Total call count for this tool on this day';



COMMENT ON COLUMN public.tool_usage_stats_old.success_count IS 'Successful call count';



COMMENT ON COLUMN public.tool_usage_stats_old.error_count IS 'Failed call count';



CREATE SEQUENCE public.tool_usage_stats_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tool_usage_stats_id_seq OWNED BY public.tool_usage_stats_old.id;



CREATE TABLE public.topup_packages (
    id integer NOT NULL,
    code character varying(32) NOT NULL,
    tier character varying(16) NOT NULL,
    name character varying(128) NOT NULL,
    price_cents integer NOT NULL,
    credits_amount bigint NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT topup_packages_tier_check CHECK (((tier)::text = ANY (ARRAY[('small'::character varying)::text, ('medium'::character varying)::text, ('large'::character varying)::text])))
);



CREATE SEQUENCE public.topup_packages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.topup_packages_id_seq OWNED BY public.topup_packages.id;



CREATE TABLE public.toxic_keywords (
    id integer NOT NULL,
    keyword character varying(100) NOT NULL,
    category character varying(50) NOT NULL,
    severity integer NOT NULL,
    language character varying(10) DEFAULT 'zh'::character varying,
    enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT toxic_keywords_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);



CREATE SEQUENCE public.toxic_keywords_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.toxic_keywords_id_seq OWNED BY public.toxic_keywords.id;



CREATE TABLE public.tuning_params (
    key text NOT NULL,
    value jsonb NOT NULL,
    category text NOT NULL,
    source text DEFAULT 'default'::text NOT NULL,
    confidence numeric(4,3) DEFAULT 1.0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    description text,
    applied_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);



CREATE TABLE public.tuning_proposals (
    id bigint NOT NULL,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    category text NOT NULL,
    task_type text,
    proposal jsonb NOT NULL,
    evidence jsonb NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    reviewed_by text,
    reviewed_at timestamp with time zone,
    applied_at timestamp with time zone,
    review_note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT tuning_proposals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text, 'applied'::text, 'expired'::text])))
);



COMMENT ON TABLE public.tuning_proposals IS 'Auto-generated tuning proposals from feedback analysis. Require admin approval before applying to hot path.';



CREATE SEQUENCE public.tuning_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tuning_proposals_id_seq OWNED BY public.tuning_proposals.id;



CREATE TABLE public.tuning_signals (
    id bigint NOT NULL,
    request_id text NOT NULL,
    session_id text,
    ts timestamp with time zone DEFAULT now() NOT NULL,
    task_type text NOT NULL,
    classifier text NOT NULL,
    confidence numeric(4,3),
    chosen_model text,
    canonical_id integer,
    success_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    latency_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    cost_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    drift_flag boolean DEFAULT false NOT NULL,
    quality_score numeric(3,2) DEFAULT 0.5 NOT NULL,
    latency_ms integer,
    cost_usd numeric(10,6),
    prompt_tokens integer,
    completion_tokens integer,
    signal_payload jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    strategy text DEFAULT 'pattern_layered'::text NOT NULL,
    CONSTRAINT tuning_signals_strategy_check CHECK ((strategy = ANY (ARRAY['baseline_heuristic'::text, 'pattern_layered'::text, 'llm_fallback'::text])))
);



COMMENT ON TABLE public.tuning_signals IS 'Implicit feedback signals for auto-route tuning. Written async per-request, analyzed daily by feedback_analyzer.';



CREATE MATERIALIZED VIEW public.tuning_signals_5m AS
 SELECT (date_trunc('hour'::text, tuning_signals.ts) + (floor((((EXTRACT(minute FROM tuning_signals.ts))::integer / 5))::double precision) * '00:05:00'::interval)) AS bucket,
    tuning_signals.task_type,
    tuning_signals.classifier,
    count(*) AS total,
    avg(tuning_signals.quality_score) AS avg_quality,
    avg(tuning_signals.success_score) AS avg_success,
    avg(tuning_signals.latency_score) AS avg_latency,
    avg(tuning_signals.cost_score) AS avg_cost,
    ((sum(
        CASE
            WHEN tuning_signals.drift_flag THEN 1
            ELSE 0
        END))::double precision / (NULLIF(count(*), 0))::double precision) AS drift_rate
   FROM public.tuning_signals
  WHERE (tuning_signals.ts >= (now() - '7 days'::interval))
  GROUP BY (date_trunc('hour'::text, tuning_signals.ts) + (floor((((EXTRACT(minute FROM tuning_signals.ts))::integer / 5))::double precision) * '00:05:00'::interval)), tuning_signals.task_type, tuning_signals.classifier
  WITH NO DATA;



CREATE MATERIALIZED VIEW public.tuning_signals_daily AS
 SELECT date_trunc('day'::text, tuning_signals.ts) AS bucket,
    tuning_signals.task_type,
    tuning_signals.classifier,
    count(*) AS total,
    avg(tuning_signals.quality_score) AS avg_quality,
    avg(tuning_signals.success_score) AS avg_success,
    avg(tuning_signals.latency_score) AS avg_latency,
    avg(tuning_signals.cost_score) AS avg_cost,
    ((sum(
        CASE
            WHEN tuning_signals.drift_flag THEN 1
            ELSE 0
        END))::double precision / (NULLIF(count(*), 0))::double precision) AS drift_rate
   FROM public.tuning_signals
  WHERE (tuning_signals.ts >= (now() - '90 days'::interval))
  GROUP BY (date_trunc('day'::text, tuning_signals.ts)), tuning_signals.task_type, tuning_signals.classifier
  WITH NO DATA;



CREATE SEQUENCE public.tuning_signals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.tuning_signals_id_seq OWNED BY public.tuning_signals.id;



CREATE TABLE public.usage_ledger (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
)
PARTITION BY RANGE (ts);




CREATE TABLE public.usage_ledger_2026_06 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);




CREATE TABLE public.usage_ledger_2026_07 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);




CREATE TABLE public.usage_ledger_2026_07_columnar_backup (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);




CREATE TABLE public.usage_ledger_2026_08 (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);



CREATE TABLE public.usage_ledger_default (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);



CREATE TABLE public.usage_ledger_old (
    request_id text NOT NULL,
    ts timestamp with time zone NOT NULL,
    tenant_id text NOT NULL,
    application_id integer,
    api_key_id integer,
    end_user_id text,
    credential_id integer,
    provider_id integer,
    canonical_id integer,
    raw_model_name text,
    prompt_tokens integer,
    completion_tokens integer,
    cache_read_tokens integer,
    cache_write_tokens integer,
    total_tokens integer,
    cost_usd numeric(12,6),
    latency_ms integer,
    success boolean,
    error_kind text
);



CREATE TABLE public.usage_minute (
    bucket timestamp with time zone NOT NULL,
    tenant_id text DEFAULT 'default'::text NOT NULL,
    application_id bigint,
    api_key_id bigint,
    end_user_id text,
    department text,
    employee text,
    "position" text,
    credential_id bigint,
    provider_id bigint,
    canonical_id bigint,
    requests bigint DEFAULT 0 NOT NULL,
    prompt_tokens bigint DEFAULT 0 NOT NULL,
    completion_tokens bigint DEFAULT 0 NOT NULL,
    total_tokens bigint DEFAULT 0 NOT NULL,
    cost_usd numeric(18,8) DEFAULT 0 NOT NULL,
    errors bigint DEFAULT 0 NOT NULL
);



CREATE TABLE public.users (
    id integer NOT NULL,
    tenant_id character varying(64) DEFAULT 'default'::character varying NOT NULL,
    username character varying(128) NOT NULL,
    password_hash character varying(256) NOT NULL,
    display_name character varying(128) DEFAULT ''::character varying NOT NULL,
    email character varying(256) DEFAULT ''::character varying NOT NULL,
    role character varying(32) DEFAULT 'tenant_admin'::character varying NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    last_login_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    must_change_password boolean DEFAULT false NOT NULL
);



CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;



CREATE VIEW public.v_candidate_failure_logs_diagnosis AS
 SELECT cfl.id,
    cfl.ts,
    cfl.tenant_id,
    cfl.credential_id,
    cfl.provider_id,
    cfl.raw_model_name,
    cfl.attempt_index,
    cfl.error_kind AS legacy_kind,
    COALESCE(cfl.upstream_status_code,
        CASE
            WHEN (cfl.error_message ~ 'upstream [0-9]+:'::text) THEN ("substring"(cfl.error_message, 'upstream ([0-9]+):'::text))::integer
            ELSE NULL::integer
        END) AS extracted_upstream_status_code,
    public.diagnose_failure_kind(COALESCE(cfl.upstream_status_code,
        CASE
            WHEN (cfl.error_message ~ 'upstream [0-9]+:'::text) THEN ("substring"(cfl.error_message, 'upstream ([0-9]+):'::text))::integer
            ELSE NULL::integer
        END), COALESCE(NULLIF(cfl.upstream_response_body, ''::text), cfl.error_message, ''::text)) AS diagnosed_error_kind,
    cfl.upstream_status_code AS live_upstream_status_code,
    cfl.latency_ms,
    cfl.per_attempt_latency_ms,
    cfl.retryable,
    cfl.error_message,
    (cfl.error_kind IS DISTINCT FROM public.diagnose_failure_kind(COALESCE(cfl.upstream_status_code,
        CASE
            WHEN (cfl.error_message ~ 'upstream [0-9]+:'::text) THEN ("substring"(cfl.error_message, 'upstream ([0-9]+):'::text))::integer
            ELSE NULL::integer
        END), COALESCE(NULLIF(cfl.upstream_response_body, ''::text), cfl.error_message, ''::text))) AS classification_disagrees
   FROM public.candidate_failure_logs cfl;



COMMENT ON VIEW public.v_candidate_failure_logs_diagnosis IS '2026-06-30 (migration 057). Computes the post-P2 classifier
     output (diagnosed_error_kind) for every candidate_failure_logs
     row, recovering the upstream HTTP status code from
     error_message via the "upstream NNN:" regex. Side-by-side
     legacy_kind vs diagnosed_error_kind for incident review.
     Companion to v_request_failures_diagnosis (migration 056).';



CREATE VIEW public.v_format_anomaly_summary AS
 SELECT date_trunc('hour'::text, response_format_anomalies.detected_at) AS hour,
    response_format_anomalies.provider_code,
    response_format_anomalies.client_model,
    response_format_anomalies.anomaly_type,
    response_format_anomalies.severity,
    count(*) AS anomaly_count,
    count(DISTINCT response_format_anomalies.request_id) AS affected_requests,
    avg(response_format_anomalies.content_size_bytes) AS avg_content_size,
    avg(response_format_anomalies.expected_tokens) AS avg_expected_tokens,
    avg(response_format_anomalies.actual_tokens) AS avg_actual_tokens,
    count(*) FILTER (WHERE response_format_anomalies.resolved) AS resolved_count
   FROM public.response_format_anomalies
  WHERE (response_format_anomalies.detected_at > (now() - '7 days'::interval))
  GROUP BY (date_trunc('hour'::text, response_format_anomalies.detected_at)), response_format_anomalies.provider_code, response_format_anomalies.client_model, response_format_anomalies.anomaly_type, response_format_anomalies.severity;



CREATE VIEW public.v_fp_slot_policy AS
 SELECT COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::boolean AS bool
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_enabled'::text)), true) AS enabled,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_max_per_credential'::text)), 100) AS max_per_credential,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::numeric AS "numeric"
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_default_ratio'::text)), 0.25) AS default_ratio,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_client_fingerprint_ttl_days'::text)), 30) AS client_ttl_days,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_max_total_clients'::text)), 10000) AS max_total_clients;



COMMENT ON VIEW public.v_fp_slot_policy IS 'Active fingerprint-slot policy derived from settings_kv. Used by admin UI and the credentialfpslot manager at boot.';



CREATE VIEW public.v_idle_credential_slots AS
 SELECT model_probe_state.credential_id,
    model_probe_state.raw_model_name,
    model_probe_state.state,
    model_probe_state.consecutive_failures,
    model_probe_state.last_attempt_at,
    (EXTRACT(epoch FROM (now() - model_probe_state.last_attempt_at)))::integer AS idle_seconds
   FROM public.model_probe_state
  WHERE (model_probe_state.state <> 'broken_confirmed'::text);



COMMENT ON VIEW public.v_idle_credential_slots IS 'For monitoring: per-binding rows with last_attempt_at and idle_seconds. Used by admin dashboards to spot slots that need reclaim.';



CREATE VIEW public.v_model_availability_timeline AS
 SELECT mpr.raw_model_name,
    mpr.raw_model_name AS outbound_model_name,
    date_trunc('hour'::text, mpr.created_at) AS hour_bucket,
    count(*) AS total_probes,
    count(*) FILTER (WHERE (mpr.status = 'ok'::text)) AS successful_probes,
    count(*) FILTER (WHERE (mpr.status <> 'ok'::text)) AS failed_probes,
    round((((count(*) FILTER (WHERE (mpr.status = 'ok'::text)))::numeric * 100.0) / (count(*))::numeric), 2) AS success_rate,
    avg(mpr.latency_ms) FILTER (WHERE (mpr.status = 'ok'::text)) AS avg_latency_ms,
    count(DISTINCT mpr.credential_id) AS probed_credentials,
    count(DISTINCT mpr.credential_id) FILTER (WHERE (mpr.status = 'ok'::text)) AS successful_credentials,
    count(DISTINCT mpr.credential_id) FILTER (WHERE (mpr.status <> 'ok'::text)) AS failed_credentials
   FROM public.model_probe_runs mpr
  WHERE (mpr.created_at >= (now() - '24:00:00'::interval))
  GROUP BY mpr.raw_model_name, (date_trunc('hour'::text, mpr.created_at))
  ORDER BY mpr.raw_model_name, (date_trunc('hour'::text, mpr.created_at)) DESC;



CREATE VIEW public.v_model_health_dashboard AS
 WITH model_stats AS (
         SELECT mps.raw_model_name,
            mps.raw_model_name AS outbound_model_name,
            'openai-completions'::text AS protocol,
            p.display_name AS provider_name,
            count(*) AS total_credentials,
            count(*) FILTER (WHERE (mps.state = ANY (ARRAY['healthy_confirmed'::text, 'healthy'::text]))) AS healthy_count,
            count(*) FILTER (WHERE (mps.state = 'suspicious'::text)) AS suspicious_count,
            count(*) FILTER (WHERE (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text]))) AS failing_count,
            count(*) FILTER (WHERE (mps.state = 'probing'::text)) AS probing_count,
            sum(
                CASE
                    WHEN (mps.consecutive_failures >= 3) THEN 1
                    ELSE 0
                END) AS urgent_count,
            count(*) FILTER (WHERE (mps.state = 'suspicious'::text)) AS suspicious_priority_count,
            count(*) FILTER (WHERE (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text]))) AS failing_priority_count,
            count(*) FILTER (WHERE (mps.state = 'healthy_confirmed'::text)) AS watchdog_count,
            avg(
                CASE
                    WHEN (mps.total_attempts > 0) THEN (((mps.consecutive_successes)::double precision / (mps.total_attempts)::double precision) * (100)::double precision)
                    ELSE NULL::double precision
                END) AS avg_success_rate_7d,
            avg((EXTRACT(epoch FROM (mps.next_retry_at - now())) / (3600)::numeric)) AS avg_verification_hours,
            avg(mps.consecutive_successes) AS avg_consecutive_successes,
            0 AS total_real_success_24h,
            0 AS total_real_failure_24h,
            max(mps.last_attempt_at) AS last_verified_at,
            max(mps.last_attempt_at) AS last_real_request_at,
            min(mps.next_retry_at) AS next_probe_at,
            sum(
                CASE
                    WHEN ((mps.state = ANY (ARRAY['failing'::text, 'broken_confirmed'::text])) AND (mps.consecutive_failures >= 3)) THEN 1
                    ELSE 0
                END) AS critical_nodes,
            count(*) FILTER (WHERE ((mps.next_retry_at <= (now() + '00:05:00'::interval)) AND (mps.state <> 'probing'::text))) AS pending_probes_5min
           FROM ((public.model_probe_state mps
             JOIN public.credentials c ON ((c.id = mps.credential_id)))
             JOIN public.providers p ON ((p.id = c.provider_id)))
          WHERE ((COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false))
          GROUP BY mps.raw_model_name, p.display_name
        )
 SELECT 0 AS provider_model_id,
    model_stats.raw_model_name,
    model_stats.outbound_model_name,
    model_stats.protocol,
    model_stats.provider_name,
    model_stats.total_credentials,
    model_stats.healthy_count,
    model_stats.suspicious_count,
    model_stats.failing_count,
    model_stats.probing_count,
    round((((model_stats.healthy_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) AS healthy_percentage,
    round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) AS failing_percentage,
    model_stats.urgent_count,
    model_stats.suspicious_priority_count,
    model_stats.failing_priority_count,
    model_stats.watchdog_count,
    round((model_stats.avg_success_rate_7d)::numeric, 2) AS avg_success_rate_7d,
    round(model_stats.avg_verification_hours, 1) AS avg_verification_hours,
    round(model_stats.avg_consecutive_successes, 1) AS avg_consecutive_successes,
    model_stats.total_real_success_24h,
    model_stats.total_real_failure_24h,
        CASE
            WHEN ((model_stats.total_real_success_24h + model_stats.total_real_failure_24h) > 0) THEN round((((model_stats.total_real_success_24h)::numeric * 100.0) / ((model_stats.total_real_success_24h + model_stats.total_real_failure_24h))::numeric), 2)
            ELSE NULL::numeric
        END AS real_success_rate_24h,
    model_stats.last_verified_at,
    model_stats.last_real_request_at,
    model_stats.next_probe_at,
    model_stats.critical_nodes,
    model_stats.pending_probes_5min,
        CASE
            WHEN (model_stats.critical_nodes > 0) THEN 'critical'::text
            WHEN (round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) > (20)::numeric) THEN 'warning'::text
            WHEN (round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) > (10)::numeric) THEN 'degraded'::text
            WHEN (round((((model_stats.healthy_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) >= (90)::numeric) THEN 'healthy'::text
            ELSE 'normal'::text
        END AS overall_health
   FROM model_stats
  ORDER BY
        CASE
            WHEN (model_stats.critical_nodes > 0) THEN 1
            WHEN (model_stats.urgent_count > 0) THEN 2
            WHEN (round((((model_stats.failing_count)::numeric * 100.0) / (NULLIF(model_stats.total_credentials, 0))::numeric), 1) > (20)::numeric) THEN 3
            ELSE 4
        END, model_stats.total_credentials DESC, model_stats.raw_model_name;



CREATE VIEW public.v_model_priority_details AS
 SELECT mps.raw_model_name,
    mps.raw_model_name AS outbound_model_name,
        CASE
            WHEN (mps.consecutive_failures >= 3) THEN 'urgent'::text
            WHEN (mps.state = 'suspicious'::text) THEN 'suspicious'::text
            WHEN (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text])) THEN 'failing'::text
            ELSE 'watchdog'::text
        END AS probe_priority,
    mps.state,
    c.id AS credential_id,
    c.label AS credential_label,
    p.display_name AS provider_name,
    mps.last_attempt_at AS last_verified_at,
    mps.next_retry_at,
    mps.last_attempt_at AS marked_suspicious_at,
    NULL::timestamp without time zone AS probing_started_at,
    mps.consecutive_successes,
    mps.consecutive_failures,
    0 AS consecutive_watchdog_successes,
        CASE
            WHEN (mps.total_attempts > 0) THEN (((mps.consecutive_successes)::double precision / (mps.total_attempts)::double precision) * (100)::double precision)
            ELSE NULL::double precision
        END AS success_rate_7d,
    (mps.next_retry_at - now()) AS verification_interval,
    0 AS real_success_24h,
    0 AS real_failure_24h,
    mps.last_attempt_at AS last_real_request_at,
    NULL::text AS last_unavailable_reason,
    mps.last_status AS last_err_code,
        CASE
            WHEN (mps.next_retry_at <= now()) THEN 'ready'::text
            WHEN (mps.next_retry_at <= (now() + '00:01:00'::interval)) THEN '<1min'::text
            WHEN (mps.next_retry_at <= (now() + '00:05:00'::interval)) THEN '<5min'::text
            WHEN (mps.next_retry_at <= (now() + '01:00:00'::interval)) THEN '<1h'::text
            ELSE '>1h'::text
        END AS retry_in,
    (EXTRACT(epoch FROM (now() - mps.last_attempt_at)) / (60)::numeric) AS state_duration_minutes
   FROM ((public.model_probe_state mps
     JOIN public.credentials c ON ((c.id = mps.credential_id)))
     JOIN public.providers p ON ((p.id = c.provider_id)))
  WHERE ((COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false))
  ORDER BY mps.raw_model_name,
        CASE
            WHEN (mps.consecutive_failures >= 3) THEN 1
            WHEN (mps.state = 'suspicious'::text) THEN 2
            WHEN (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text])) THEN 3
            ELSE 4
        END, c.id;



CREATE VIEW public.v_probe_queue_snapshot AS
 SELECT sub.probe_priority,
    sub.state,
    count(*) AS queue_size,
    count(*) FILTER (WHERE (sub.next_retry_at <= now())) AS ready_now,
    count(*) FILTER (WHERE (sub.next_retry_at <= (now() + '00:01:00'::interval))) AS ready_1min,
    count(*) FILTER (WHERE (sub.next_retry_at <= (now() + '00:05:00'::interval))) AS ready_5min,
    min(sub.next_retry_at) AS earliest_retry_at,
    max(sub.next_retry_at) AS latest_retry_at,
    avg(EXTRACT(epoch FROM (now() - sub.last_attempt_at))) AS avg_wait_seconds,
    max(EXTRACT(epoch FROM (now() - sub.last_attempt_at))) AS max_wait_seconds
   FROM ( SELECT
                CASE
                    WHEN (mps.consecutive_failures >= 3) THEN 'urgent'::text
                    WHEN (mps.state = 'suspicious'::text) THEN 'suspicious'::text
                    WHEN (mps.state = ANY (ARRAY['failing'::text, 'recovering'::text])) THEN 'failing'::text
                    WHEN (mps.state = 'healthy_confirmed'::text) THEN 'watchdog'::text
                    ELSE NULL::text
                END AS probe_priority,
            mps.state,
            mps.next_retry_at,
            mps.last_attempt_at
           FROM (public.model_probe_state mps
             JOIN public.credentials c ON ((c.id = mps.credential_id)))
          WHERE ((mps.state = ANY (ARRAY['suspicious'::text, 'failing'::text, 'recovering'::text])) AND (COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false))) sub
  GROUP BY sub.probe_priority, sub.state
  ORDER BY
        CASE
            WHEN (sub.probe_priority = 'urgent'::text) THEN 1
            WHEN (sub.probe_priority = 'suspicious'::text) THEN 2
            WHEN (sub.probe_priority = 'failing'::text) THEN 3
            WHEN (sub.probe_priority = 'watchdog'::text) THEN 4
            ELSE 5
        END, sub.state;



CREATE VIEW public.v_probe_system_health AS
 SELECT ( SELECT count(*) AS count
           FROM public.model_probe_state) AS total_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = ANY (ARRAY['healthy_confirmed'::text, 'healthy'::text]))) AS healthy_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = ANY (ARRAY['failing'::text, 'broken_confirmed'::text]))) AS failing_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'suspicious'::text)) AS suspicious_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'probing'::text)) AS probing_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.consecutive_failures >= 3)) AS urgent_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'suspicious'::text)) AS suspicious_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = ANY (ARRAY['failing'::text, 'recovering'::text]))) AS failing_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'healthy_confirmed'::text)) AS watchdog_queue_size,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE ((model_probe_state.next_retry_at <= now()) AND (model_probe_state.state <> 'probing'::text))) AS ready_probes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'probing'::text)) AS current_probing,
    ( SELECT count(DISTINCT model_probe_state.credential_id) AS count
           FROM public.model_probe_state
          WHERE (model_probe_state.state = 'probing'::text)) AS credentials_being_probed,
    ( SELECT round((avg(
                CASE
                    WHEN (model_probe_state.total_attempts > 0) THEN (((model_probe_state.consecutive_successes)::double precision / (model_probe_state.total_attempts)::double precision) * (100)::double precision)
                    ELSE NULL::double precision
                END))::numeric, 2) AS round
           FROM public.model_probe_state) AS avg_success_rate_7d,
    ( SELECT max(model_probe_state.last_attempt_at) AS max
           FROM public.model_probe_state) AS last_probe_at,
    ( SELECT max(model_probe_state.last_attempt_at) AS max
           FROM public.model_probe_state) AS last_real_request_at,
    0 AS total_real_success_24h,
    0 AS total_real_failure_24h,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE ((model_probe_state.state = ANY (ARRAY['failing'::text, 'broken_confirmed'::text])) AND (model_probe_state.consecutive_failures >= 5))) AS critical_nodes,
    ( SELECT count(*) AS count
           FROM public.model_probe_state
          WHERE ((model_probe_state.next_retry_at <= (now() + '00:05:00'::interval)) AND (model_probe_state.state <> 'probing'::text))) AS pending_probes_5min,
    now() AS snapshot_at;



CREATE VIEW public.v_routable_credential_models AS
 SELECT cmb.id AS binding_id,
    cmb.credential_id,
    cmb.provider_model_id,
    c.tenant_id,
    p.id AS provider_id,
    c.label AS credential_label,
    pm.raw_model_name,
    pm.canonical_id,
        CASE
            WHEN (NOT p.enabled) THEN 'provider_disabled'::text
            WHEN COALESCE(p.manual_disabled, false) THEN 'provider_manual_disabled'::text
            WHEN (c.status <> 'active'::text) THEN ('credential_status_'::text || c.status)
            WHEN (c.lifecycle_status <> 'active'::text) THEN ('lifecycle_'::text || c.lifecycle_status)
            WHEN COALESCE(c.manual_disabled, false) THEN 'credential_manual_disabled'::text
            WHEN (c.availability_state = 'cooling'::text) THEN 'availability_cooling'::text
            WHEN (c.availability_state = 'rate_limited'::text) THEN 'availability_rate_limited'::text
            WHEN (c.availability_state = 'auth_failed'::text) THEN 'availability_auth_failed'::text
            WHEN (c.availability_state = 'unreachable'::text) THEN 'availability_unreachable'::text
            WHEN (c.availability_state = 'suspended'::text) THEN 'availability_suspended'::text
            WHEN (c.quota_state = ANY (ARRAY['permanently_exhausted'::text, 'balance_exhausted'::text])) THEN ('quota_'::text || c.quota_state)
            WHEN ((c.health_status = 'unreachable'::text) AND (c.health_checked_at > (now() - '01:00:00'::interval))) THEN 'recent_probe_unreachable'::text
            WHEN (NOT pm.available) THEN 'model_unavailable'::text
            WHEN (cmb.unavailable_reason = 'manual'::text) THEN 'model_manual_disabled'::text
            WHEN (NOT cmb.available) THEN 'binding_unavailable'::text
            ELSE NULL::text
        END AS unavailable_reason,
    (p.enabled AND (COALESCE(p.manual_disabled, false) = false) AND (c.status = 'active'::text) AND (c.lifecycle_status = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false) AND (c.availability_state = 'ready'::text) AND (c.quota_state <> ALL (ARRAY['permanently_exhausted'::text, 'balance_exhausted'::text])) AND (pm.available = true) AND (cmb.available = true) AND (cmb.unavailable_reason IS DISTINCT FROM 'manual'::text) AND (COALESCE(c.health_status, 'unknown'::text) = ANY (ARRAY['healthy'::text, 'unknown'::text]))) AS is_routable,
    (((((cmb.manual_priority * 100))::numeric + (COALESCE(cmb.success_rate, 0.5) * (50)::numeric)) - (COALESCE(cmb.unit_price_in_per_1m, (0)::numeric) * 0.001)) - ((COALESCE(cmb.p95_latency_ms, 1000))::numeric * 0.01)) AS routing_score
   FROM (((public.credential_model_bindings cmb
     JOIN public.credentials c ON ((c.id = cmb.credential_id)))
     JOIN public.providers p ON ((p.id = c.provider_id)))
     JOIN public.provider_models pm ON ((pm.id = cmb.provider_model_id)));



CREATE VIEW public.v_suspicious_probe_targets AS
 SELECT mps.credential_id,
    pm.raw_model_name,
    COALESCE(pm.outbound_model_name, ''::text) AS outbound_model_name,
    COALESCE(p.base_url, ''::text) AS base_url,
    COALESCE(p.protocol, 'openai-completions'::text) AS protocol,
    mps.marked_suspicious_at,
    mps.next_retry_at,
    mps.consecutive_failures,
    mps.consecutive_successes,
    public.model_probe_credential_concurrency(mps.credential_id) AS credential_probe_count
   FROM (((public.model_probe_state mps
     JOIN public.credentials c ON ((c.id = mps.credential_id)))
     JOIN public.providers p ON ((p.id = c.provider_id)))
     JOIN public.provider_models pm ON (((pm.raw_model_name = mps.raw_model_name) AND (EXISTS ( SELECT 1
           FROM public.credential_model_bindings cmb
          WHERE ((cmb.credential_id = mps.credential_id) AND (cmb.provider_model_id = pm.id)))))))
  WHERE ((mps.state = 'suspicious'::text) AND (mps.next_retry_at <= now()) AND (COALESCE(c.status, 'active'::text) = 'active'::text) AND (COALESCE(c.lifecycle_status, 'active'::text) = 'active'::text) AND (COALESCE(c.manual_disabled, false) = false) AND (COALESCE(p.enabled, false) = true) AND (COALESCE(p.manual_disabled, false) = false) AND (public.model_probe_credential_concurrency(mps.credential_id) < 2))
  ORDER BY (public.model_probe_credential_concurrency(mps.credential_id)), mps.marked_suspicious_at, mps.next_retry_at
 LIMIT 100;



CREATE TABLE public.work_type_config (
    key text NOT NULL,
    label text NOT NULL,
    category text NOT NULL,
    l1_task_type text NOT NULL,
    default_profile text DEFAULT 'smart'::text NOT NULL,
    tags text[] DEFAULT '{}'::text[] NOT NULL,
    prompt_keywords text[] DEFAULT '{}'::text[] NOT NULL,
    acc_task_type text,
    enabled boolean DEFAULT true NOT NULL,
    sort_order integer DEFAULT 0 NOT NULL,
    synced_from_acc_at timestamp with time zone,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    system_prompt text,
    CONSTRAINT work_type_config_default_profile_check CHECK ((default_profile = ANY (ARRAY['smart'::text, 'speed_first'::text, 'cost_first'::text])))
);



COMMENT ON TABLE public.work_type_config IS 'Work type definitions (P1 seed; Phase 3 sync from ACC)';



CREATE TABLE public.work_type_model_route (
    id integer NOT NULL,
    work_type_key text NOT NULL,
    canonical_name text NOT NULL,
    weight numeric(5,2) DEFAULT 1.0 NOT NULL,
    min_score numeric(8,4) DEFAULT 0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    tier text DEFAULT 'secondary'::text NOT NULL,
    task_quality_score numeric(5,2) DEFAULT 0 NOT NULL,
    CONSTRAINT work_type_model_route_task_quality_score_check CHECK (((task_quality_score >= (0)::numeric) AND (task_quality_score <= (100)::numeric))),
    CONSTRAINT work_type_model_route_tier_check CHECK ((tier = ANY (ARRAY['primary'::text, 'secondary'::text, 'fallback'::text])))
);



COMMENT ON TABLE public.work_type_model_route IS 'Preferred model routes per work type (L1 selection hints)';



COMMENT ON COLUMN public.work_type_model_route.weight IS '同 tier 内的排序权重（tier 间优先级：primary > secondary > fallback，tier 内按 weight DESC 排）';



COMMENT ON COLUMN public.work_type_model_route.tier IS '三级偏好：primary（首选）/ secondary（次选）/ fallback（兜底）。Index.Recommend 先推荐 primary，全挂时用 secondary，最后才 fallback';



COMMENT ON COLUMN public.work_type_model_route.task_quality_score IS '该模型在该任务上的人工评分覆盖（0-100）。0 表示用公式计算 scoreStrengthMatch；>0 则直接用该分数';



CREATE SEQUENCE public.work_type_model_route_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;



ALTER SEQUENCE public.work_type_model_route_id_seq OWNED BY public.work_type_model_route.id;



ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');



ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');



ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.credential_model_index_archive ATTACH PARTITION public.credential_model_index_archive_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.credential_model_index ATTACH PARTITION public.credential_model_index_default DEFAULT;



ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');



ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');



ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');



ALTER TABLE ONLY public.request_logs_archive ATTACH PARTITION public.request_logs_archive_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_default DEFAULT;



ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');



ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');



ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_default DEFAULT;



ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');



ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.routing_decision_log_archive ATTACH PARTITION public.routing_decision_log_archive_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_default DEFAULT;



ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');



ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');



ALTER TABLE ONLY public.tool_usage_stats ATTACH PARTITION public.tool_usage_stats_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');



ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_default DEFAULT;



ALTER TABLE ONLY public.agents ALTER COLUMN id SET DEFAULT nextval('public.agents_id_seq'::regclass);



ALTER TABLE ONLY public.analysis_events ALTER COLUMN id SET DEFAULT nextval('public.analysis_events_id_seq'::regclass);



ALTER TABLE ONLY public.api_keys ALTER COLUMN id SET DEFAULT nextval('public.api_keys_id_seq'::regclass);



ALTER TABLE ONLY public.applications ALTER COLUMN id SET DEFAULT nextval('public.applications_id_seq'::regclass);



ALTER TABLE ONLY public.armor_judgments ALTER COLUMN id SET DEFAULT nextval('public.armor_judgments_id_seq'::regclass);



ALTER TABLE ONLY public.auto_tune_audit ALTER COLUMN id SET DEFAULT nextval('public.auto_tune_audit_id_seq'::regclass);



ALTER TABLE ONLY public.background_tasks ALTER COLUMN id SET DEFAULT nextval('public.background_tasks_id_seq'::regclass);



ALTER TABLE ONLY public.billing_orders ALTER COLUMN id SET DEFAULT nextval('public.billing_orders_id_seq'::regclass);



ALTER TABLE ONLY public.credential_capabilities ALTER COLUMN id SET DEFAULT nextval('public.credential_capabilities_id_seq'::regclass);



ALTER TABLE ONLY public.credential_health_checks ALTER COLUMN id SET DEFAULT nextval('public.credential_health_checks_id_seq'::regclass);



ALTER TABLE ONLY public.credential_model_bindings ALTER COLUMN id SET DEFAULT nextval('public.credential_model_bindings_id_seq'::regclass);



ALTER TABLE ONLY public.credential_probe_configs ALTER COLUMN id SET DEFAULT nextval('public.credential_probe_configs_id_seq'::regclass);



ALTER TABLE ONLY public.credential_probes ALTER COLUMN id SET DEFAULT nextval('public.credential_probes_id_seq'::regclass);



ALTER TABLE ONLY public.credential_quota_usage ALTER COLUMN id SET DEFAULT nextval('public.credential_quota_usage_id_seq'::regclass);



ALTER TABLE ONLY public.credential_quotas ALTER COLUMN id SET DEFAULT nextval('public.credential_quotas_id_seq'::regclass);



ALTER TABLE ONLY public.credentials ALTER COLUMN id SET DEFAULT nextval('public.credentials_id_seq'::regclass);



ALTER TABLE ONLY public.credit_ledger ALTER COLUMN id SET DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass);



ALTER TABLE ONLY public.credit_ledger_old ALTER COLUMN id SET DEFAULT nextval('public.credit_ledger_id_seq'::regclass);



ALTER TABLE ONLY public.goal_sessions ALTER COLUMN id SET DEFAULT nextval('public.goal_sessions_id_seq'::regclass);



ALTER TABLE ONLY public.handoff_logs ALTER COLUMN id SET DEFAULT nextval('public.handoff_logs_id_seq'::regclass);



ALTER TABLE ONLY public.local_models ALTER COLUMN id SET DEFAULT nextval('public.local_models_id_seq'::regclass);



ALTER TABLE ONLY public.local_runtimes ALTER COLUMN id SET DEFAULT nextval('public.local_runtimes_id_seq'::regclass);



ALTER TABLE ONLY public.model_aliases ALTER COLUMN id SET DEFAULT nextval('public.model_aliases_id_seq'::regclass);



ALTER TABLE ONLY public.model_discovery_runs ALTER COLUMN id SET DEFAULT nextval('public.model_discovery_runs_id_seq'::regclass);



ALTER TABLE ONLY public.model_fingerprints ALTER COLUMN id SET DEFAULT nextval('public.model_fingerprints_id_seq'::regclass);



ALTER TABLE ONLY public.model_lifecycle_jobs ALTER COLUMN id SET DEFAULT nextval('public.model_lifecycle_jobs_id_seq'::regclass);



ALTER TABLE ONLY public.model_offers_legacy ALTER COLUMN id SET DEFAULT nextval('public.model_offers_id_seq'::regclass);



ALTER TABLE ONLY public.model_reconcile_log ALTER COLUMN id SET DEFAULT nextval('public.model_reconcile_log_id_seq'::regclass);



ALTER TABLE ONLY public.models_canonical ALTER COLUMN id SET DEFAULT nextval('public.models_canonical_id_seq'::regclass);



ALTER TABLE ONLY public.ops_model_offers_backup ALTER COLUMN backup_id SET DEFAULT nextval('public.ops_model_offers_backup_backup_id_seq'::regclass);



ALTER TABLE ONLY public.output_compliance_audit ALTER COLUMN id SET DEFAULT nextval('public.output_compliance_audit_id_seq'::regclass);



ALTER TABLE ONLY public.output_compliance_policies ALTER COLUMN id SET DEFAULT nextval('public.output_compliance_policies_id_seq'::regclass);



ALTER TABLE ONLY public.pii_patterns ALTER COLUMN id SET DEFAULT nextval('public.pii_patterns_id_seq'::regclass);



ALTER TABLE ONLY public.pricing_plans ALTER COLUMN id SET DEFAULT nextval('public.pricing_plans_id_seq'::regclass);



ALTER TABLE ONLY public.pricing_refresh_log ALTER COLUMN id SET DEFAULT nextval('public.pricing_refresh_log_id_seq'::regclass);



ALTER TABLE ONLY public.prompt_injection_detections ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_detections_id_seq'::regclass);



ALTER TABLE ONLY public.prompt_injection_policies ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_policies_id_seq'::regclass);



ALTER TABLE ONLY public.prompt_injection_rules ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_rules_id_seq'::regclass);



ALTER TABLE ONLY public.provider_header_profiles ALTER COLUMN id SET DEFAULT nextval('public.provider_header_profiles_id_seq'::regclass);



ALTER TABLE ONLY public.provider_models ALTER COLUMN id SET DEFAULT nextval('public.provider_models_id_seq'::regclass);



ALTER TABLE ONLY public.provider_scores ALTER COLUMN id SET DEFAULT nextval('public.provider_scores_id_seq'::regclass);



ALTER TABLE ONLY public.provider_settings ALTER COLUMN id SET DEFAULT nextval('public.provider_settings_id_seq'::regclass);



ALTER TABLE ONLY public.providers ALTER COLUMN id SET DEFAULT nextval('public.providers_id_seq'::regclass);



ALTER TABLE ONLY public.response_format_anomalies ALTER COLUMN id SET DEFAULT nextval('public.response_format_anomalies_id_seq'::regclass);



ALTER TABLE ONLY public.route_decisions ALTER COLUMN id SET DEFAULT nextval('public.route_decisions_id_seq'::regclass);



ALTER TABLE ONLY public.routing_audit_log ALTER COLUMN id SET DEFAULT nextval('public.routing_audit_log_id_seq'::regclass);



ALTER TABLE ONLY public.routing_overrides ALTER COLUMN id SET DEFAULT nextval('public.routing_overrides_id_seq'::regclass);



ALTER TABLE ONLY public.routing_overrides_audit ALTER COLUMN id SET DEFAULT nextval('public.routing_overrides_audit_id_seq'::regclass);



ALTER TABLE ONLY public.security_audit_log ALTER COLUMN id SET DEFAULT nextval('public.security_audit_log_id_seq'::regclass);



ALTER TABLE ONLY public.session_audit_records ALTER COLUMN id SET DEFAULT nextval('public.session_audit_records_id_seq'::regclass);



ALTER TABLE ONLY public.settings_audit ALTER COLUMN id SET DEFAULT nextval('public.settings_audit_id_seq'::regclass);



ALTER TABLE ONLY public.subscription_plans ALTER COLUMN id SET DEFAULT nextval('public.subscription_plans_id_seq'::regclass);



ALTER TABLE ONLY public.tenant_model_policies ALTER COLUMN id SET DEFAULT nextval('public.tenant_model_policies_id_seq'::regclass);



ALTER TABLE ONLY public.tenant_model_policies_audit ALTER COLUMN id SET DEFAULT nextval('public.tenant_model_policies_audit_id_seq'::regclass);



ALTER TABLE ONLY public.tenant_subscriptions ALTER COLUMN id SET DEFAULT nextval('public.tenant_subscriptions_id_seq'::regclass);



ALTER TABLE ONLY public.tenant_tool_policies ALTER COLUMN id SET DEFAULT nextval('public.tenant_tool_policies_id_seq'::regclass);



ALTER TABLE ONLY public.token_audit_events ALTER COLUMN id SET DEFAULT nextval('public.token_audit_events_id_seq'::regclass);



ALTER TABLE ONLY public.tool_registry ALTER COLUMN id SET DEFAULT nextval('public.tool_registry_id_seq'::regclass);



ALTER TABLE ONLY public.tool_usage_stats ALTER COLUMN id SET DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass);



ALTER TABLE ONLY public.tool_usage_stats_old ALTER COLUMN id SET DEFAULT nextval('public.tool_usage_stats_id_seq'::regclass);



ALTER TABLE ONLY public.topup_packages ALTER COLUMN id SET DEFAULT nextval('public.topup_packages_id_seq'::regclass);



ALTER TABLE ONLY public.toxic_keywords ALTER COLUMN id SET DEFAULT nextval('public.toxic_keywords_id_seq'::regclass);



ALTER TABLE ONLY public.tuning_proposals ALTER COLUMN id SET DEFAULT nextval('public.tuning_proposals_id_seq'::regclass);



ALTER TABLE ONLY public.tuning_signals ALTER COLUMN id SET DEFAULT nextval('public.tuning_signals_id_seq'::regclass);



ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);



ALTER TABLE ONLY public.work_type_model_route ALTER COLUMN id SET DEFAULT nextval('public.work_type_model_route_id_seq'::regclass);



ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.analysis_events
    ADD CONSTRAINT analysis_events_event_id_key UNIQUE (event_id);



ALTER TABLE ONLY public.analysis_events
    ADD CONSTRAINT analysis_events_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_key_hash_key UNIQUE (key_hash);



ALTER TABLE ONLY public.api_keys
    ADD CONSTRAINT api_keys_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_tenant_id_code_key UNIQUE (tenant_id, code);



ALTER TABLE ONLY public.approval_queue
    ADD CONSTRAINT approval_queue_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.armor_judgments
    ADD CONSTRAINT armor_judgments_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.attachments
    ADD CONSTRAINT attachments_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.background_tasks
    ADD CONSTRAINT background_tasks_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.billing_orders
    ADD CONSTRAINT billing_orders_order_no_key UNIQUE (order_no);



ALTER TABLE ONLY public.credential_model_bindings
    ADD CONSTRAINT cmb_unique_credential_model UNIQUE (credential_id, provider_model_id);



ALTER TABLE ONLY public.credential_capabilities
    ADD CONSTRAINT credential_capabilities_credential_id_capability_key UNIQUE (credential_id, capability);



ALTER TABLE ONLY public.credential_model_call_history
    ADD CONSTRAINT credential_model_call_history_pkey PRIMARY KEY (credential_id, raw_model, window_start);



ALTER TABLE ONLY public.credential_probe_configs
    ADD CONSTRAINT credential_probe_configs_credential_id_probe_model_key UNIQUE (credential_id, probe_model);



ALTER TABLE ONLY public.credential_probe_configs
    ADD CONSTRAINT credential_probe_configs_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.credential_probes
    ADD CONSTRAINT credential_probes_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.credential_quota_usage
    ADD CONSTRAINT credential_quota_usage_quota_id_window_started_at_key UNIQUE (quota_id, window_started_at);



ALTER TABLE ONLY public.credential_quotas
    ADD CONSTRAINT credential_quotas_credential_id_quota_name_key UNIQUE (credential_id, quota_name);



ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.credentials
    ADD CONSTRAINT credentials_unique_provider_label UNIQUE (provider_id, tenant_id, label);



ALTER TABLE ONLY public.credit_ledger
    ADD CONSTRAINT credit_ledger_partitioned_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.credit_ledger_2026_06
    ADD CONSTRAINT credit_ledger_2026_06_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.credit_ledger_2026_07
    ADD CONSTRAINT credit_ledger_2026_07_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.credit_ledger_2026_08
    ADD CONSTRAINT credit_ledger_2026_08_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.goal_sessions
    ADD CONSTRAINT goal_sessions_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.goal_sessions
    ADD CONSTRAINT goal_sessions_session_id_key UNIQUE (session_id);



ALTER TABLE ONLY public.handoff_logs
    ADD CONSTRAINT handoff_logs_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.intent_aggregates
    ADD CONSTRAINT intent_aggregates_pkey PRIMARY KEY (tenant_id, intent_kind);



ALTER TABLE ONLY public.local_models
    ADD CONSTRAINT local_models_runtime_id_raw_name_key UNIQUE (runtime_id, raw_name);



ALTER TABLE ONLY public.local_runtimes
    ADD CONSTRAINT local_runtimes_host_code_runtime_type_base_url_key UNIQUE (host_code, runtime_type, base_url);



ALTER TABLE ONLY public.maas_settings
    ADD CONSTRAINT maas_settings_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.model_aliases
    ADD CONSTRAINT model_aliases_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.model_fingerprints
    ADD CONSTRAINT model_fingerprints_credential_id_canonical_id_key UNIQUE (credential_id, canonical_id);



ALTER TABLE ONLY public.model_offers_legacy
    ADD CONSTRAINT model_offers_credential_id_raw_model_name_key UNIQUE (credential_id, raw_model_name);



ALTER TABLE ONLY public.model_probe_state
    ADD CONSTRAINT model_probe_state_pkey PRIMARY KEY (credential_id, raw_model_name);



ALTER TABLE ONLY public.model_task_index
    ADD CONSTRAINT model_task_index_bucket_canonical_task_key UNIQUE (bucket, canonical_id, task_type);



ALTER TABLE ONLY public.models_canonical
    ADD CONSTRAINT models_canonical_canonical_name_key UNIQUE (canonical_name);



ALTER TABLE ONLY public.output_compliance_audit
    ADD CONSTRAINT output_compliance_audit_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT output_compliance_policies_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.passive_probe_state
    ADD CONSTRAINT passive_probe_state_pkey PRIMARY KEY (credential_id, raw_model_name, error_kind);



ALTER TABLE ONLY public.pii_patterns
    ADD CONSTRAINT pii_patterns_pattern_name_key UNIQUE (pattern_name);



ALTER TABLE ONLY public.pii_patterns
    ADD CONSTRAINT pii_patterns_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT pk_agent_relationships PRIMARY KEY (src_agent_id, dst_agent_id, rel);



ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT pk_asset_relationships PRIMARY KEY (src_kind, src_ref_id, dst_kind, dst_ref_id, rel);



ALTER TABLE ONLY public.assets
    ADD CONSTRAINT pk_assets PRIMARY KEY (kind, ref_id);



ALTER TABLE ONLY public.prompt_injection_detections
    ADD CONSTRAINT prompt_injection_detections_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT prompt_injection_policies_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.prompt_injection_rules
    ADD CONSTRAINT prompt_injection_rules_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.prompt_injection_rules
    ADD CONSTRAINT prompt_injection_rules_rule_name_key UNIQUE (rule_name);



ALTER TABLE ONLY public.provider_header_profiles
    ADD CONSTRAINT provider_header_profiles_profile_code_key UNIQUE (profile_code);



ALTER TABLE ONLY public.provider_models
    ADD CONSTRAINT provider_models_unique_provider_model UNIQUE (provider_id, raw_model_name);



ALTER TABLE ONLY public.provider_quality_rollup
    ADD CONSTRAINT provider_quality_rollup_pkey PRIMARY KEY (provider_id, bucket_start);



ALTER TABLE ONLY public.provider_settings
    ADD CONSTRAINT provider_settings_unique_key UNIQUE (provider_id, setting_key);



ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_tenant_id_code_key UNIQUE (tenant_id, code);



ALTER TABLE ONLY public.request_wal
    ADD CONSTRAINT request_wal_pkey PRIMARY KEY (request_id, created_at);



ALTER TABLE ONLY public.request_wal_2026_06
    ADD CONSTRAINT request_wal_2026_06_col_pkey PRIMARY KEY (request_id, created_at);



ALTER TABLE ONLY public.request_wal_2026_07_columnar
    ADD CONSTRAINT request_wal_2026_07_col_pkey PRIMARY KEY (request_id, created_at);



ALTER TABLE ONLY public.request_wal_2026_07
    ADD CONSTRAINT request_wal_2026_07_pkey PRIMARY KEY (request_id, created_at);



ALTER TABLE ONLY public.request_wal_2026_08
    ADD CONSTRAINT request_wal_2026_08_pkey PRIMARY KEY (request_id, created_at);



ALTER TABLE ONLY public.request_wal_default
    ADD CONSTRAINT request_wal_default_pkey PRIMARY KEY (request_id, created_at);



ALTER TABLE ONLY public.response_format_anomalies
    ADD CONSTRAINT response_format_anomalies_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.session_audit_records
    ADD CONSTRAINT session_audit_records_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT session_summaries_pkey PRIMARY KEY (session_key);



ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_code_key UNIQUE (code);



ALTER TABLE ONLY public.system_identity_pool
    ADD CONSTRAINT system_identity_pool_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.tenant_model_policies
    ADD CONSTRAINT tenant_model_policies_tenant_id_canonical_name_key UNIQUE (tenant_id, canonical_name);



ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (code);



ALTER TABLE ONLY public.tool_registry
    ADD CONSTRAINT tool_registry_tool_name_key UNIQUE (tool_name);



ALTER TABLE ONLY public.tool_usage_stats
    ADD CONSTRAINT tool_usage_stats_partitioned_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.tool_usage_stats_2026_06
    ADD CONSTRAINT tool_usage_stats_2026_06_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.tool_usage_stats
    ADD CONSTRAINT tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key UNIQUE (tool_id, tenant_id, usage_date, created_at);



ALTER TABLE ONLY public.tool_usage_stats_2026_06
    ADD CONSTRAINT tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);



ALTER TABLE ONLY public.tool_usage_stats_2026_07
    ADD CONSTRAINT tool_usage_stats_2026_07_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.tool_usage_stats_2026_07
    ADD CONSTRAINT tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);



ALTER TABLE ONLY public.tool_usage_stats_2026_08
    ADD CONSTRAINT tool_usage_stats_2026_08_pkey PRIMARY KEY (id, created_at);



ALTER TABLE ONLY public.tool_usage_stats_2026_08
    ADD CONSTRAINT tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key UNIQUE (tool_id, tenant_id, usage_date, created_at);



ALTER TABLE ONLY public.topup_packages
    ADD CONSTRAINT topup_packages_code_key UNIQUE (code);



ALTER TABLE ONLY public.toxic_keywords
    ADD CONSTRAINT toxic_keywords_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.tenant_tool_policies
    ADD CONSTRAINT uk_tenant_tool_policy UNIQUE (tenant_id, tool_pattern);



ALTER TABLE ONLY public.tool_usage_stats_old
    ADD CONSTRAINT uk_tool_usage_stats UNIQUE (tool_id, tenant_id, usage_date);



ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT unique_output_compliance_tenant UNIQUE (tenant_id);



ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT unique_tenant_policy UNIQUE (tenant_id);



ALTER TABLE ONLY public.usage_ledger
    ADD CONSTRAINT usage_ledger_partitioned_request_id_ts_key UNIQUE (request_id, ts);



ALTER TABLE ONLY public.usage_ledger_2026_06
    ADD CONSTRAINT usage_ledger_2026_06_col_request_id_ts_key UNIQUE (request_id, ts);



ALTER TABLE ONLY public.usage_ledger_2026_07_columnar_backup
    ADD CONSTRAINT usage_ledger_2026_07_col_request_id_ts_key UNIQUE (request_id, ts);



ALTER TABLE ONLY public.usage_ledger_2026_07
    ADD CONSTRAINT usage_ledger_2026_07_request_id_ts_key UNIQUE (request_id, ts);



ALTER TABLE ONLY public.usage_ledger_2026_08
    ADD CONSTRAINT usage_ledger_2026_08_heap_request_id_ts_key UNIQUE (request_id, ts);



ALTER TABLE ONLY public.usage_ledger_default
    ADD CONSTRAINT usage_ledger_default_request_id_ts_key UNIQUE (request_id, ts);



ALTER TABLE ONLY public.usage_ledger_old
    ADD CONSTRAINT usage_ledger_pkey PRIMARY KEY (request_id);



ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);



ALTER TABLE ONLY public.work_type_config
    ADD CONSTRAINT work_type_config_pkey PRIMARY KEY (key);



ALTER TABLE ONLY public.work_type_model_route
    ADD CONSTRAINT work_type_model_route_pkey PRIMARY KEY (id);



ALTER TABLE ONLY public.work_type_model_route
    ADD CONSTRAINT work_type_model_route_work_type_key_canonical_name_key UNIQUE (work_type_key, canonical_name);



CREATE UNIQUE INDEX credential_model_index_bucket_cred_model_key ON ONLY public.credential_model_index USING btree (bucket, credential_id, raw_model);



CREATE UNIQUE INDEX credential_model_index_2026_0_bucket_credential_id_raw_mod_idx1 ON public.credential_model_index_2026_08 USING btree (bucket, credential_id, raw_model);



CREATE UNIQUE INDEX credential_model_index_2026_0_bucket_credential_id_raw_mod_idx3 ON public.credential_model_index_2026_06 USING btree (bucket, credential_id, raw_model);



CREATE UNIQUE INDEX credential_model_index_2026_0_bucket_credential_id_raw_mode_idx ON public.credential_model_index_2026_07 USING btree (bucket, credential_id, raw_model);



CREATE INDEX idx_cmi_archive_cred_model ON ONLY public.credential_model_index_archive USING btree (credential_id, raw_model, bucket DESC);



CREATE INDEX credential_model_index_archiv_credential_id_raw_model_bucke_idx ON public.credential_model_index_archive_2026_08 USING btree (credential_id, raw_model, bucket DESC);



CREATE INDEX idx_cmi_archive_bucket ON ONLY public.credential_model_index_archive USING btree (bucket DESC);



CREATE INDEX credential_model_index_archive_2026_08_bucket_idx ON public.credential_model_index_archive_2026_08 USING btree (bucket DESC);



CREATE INDEX idx_cmi_archive_canonical ON ONLY public.credential_model_index_archive USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);



CREATE INDEX credential_model_index_archive_2026_08_canonical_id_bucket_idx ON public.credential_model_index_archive_2026_08 USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);



CREATE UNIQUE INDEX credential_model_index_defaul_bucket_credential_id_raw_mode_idx ON public.credential_model_index_default USING btree (bucket, credential_id, raw_model);



CREATE INDEX idx_credit_ledger_part_created ON ONLY public.credit_ledger USING btree (created_at);



CREATE INDEX credit_ledger_2026_06_created_at_idx ON public.credit_ledger_2026_06 USING btree (created_at);



CREATE INDEX idx_credit_ledger_part_ref ON ONLY public.credit_ledger USING btree (ref_type, ref_id);



CREATE INDEX credit_ledger_2026_06_ref_type_ref_id_idx ON public.credit_ledger_2026_06 USING btree (ref_type, ref_id);



CREATE INDEX idx_credit_ledger_part_tenant ON ONLY public.credit_ledger USING btree (tenant_id, created_at);



CREATE INDEX credit_ledger_2026_06_tenant_id_created_at_idx ON public.credit_ledger_2026_06 USING btree (tenant_id, created_at);



CREATE INDEX credit_ledger_2026_07_created_at_idx ON public.credit_ledger_2026_07 USING btree (created_at);



CREATE INDEX credit_ledger_2026_07_ref_type_ref_id_idx ON public.credit_ledger_2026_07 USING btree (ref_type, ref_id);



CREATE INDEX credit_ledger_2026_07_tenant_id_created_at_idx ON public.credit_ledger_2026_07 USING btree (tenant_id, created_at);



CREATE INDEX credit_ledger_2026_08_created_at_idx ON public.credit_ledger_2026_08 USING btree (created_at);



CREATE INDEX credit_ledger_2026_08_ref_type_ref_id_idx ON public.credit_ledger_2026_08 USING btree (ref_type, ref_id);



CREATE INDEX credit_ledger_2026_08_tenant_id_created_at_idx ON public.credit_ledger_2026_08 USING btree (tenant_id, created_at);



CREATE INDEX idx_agent_rel_dst ON public.agent_relationships USING btree (dst_agent_id);



CREATE INDEX idx_agent_rel_src ON public.agent_relationships USING btree (src_agent_id);



CREATE INDEX idx_agents_capabilities ON public.agents USING gin (capabilities jsonb_path_ops);



CREATE INDEX idx_agents_heartbeat ON public.agents USING btree (last_heartbeat) WHERE (last_heartbeat IS NOT NULL);



CREATE INDEX idx_agents_kind ON public.agents USING btree (tenant_id, kind);



CREATE INDEX idx_agents_tenant ON public.agents USING btree (tenant_id);



CREATE INDEX idx_analysis_events_session ON public.analysis_events USING btree (session_id, occurred_at DESC) WHERE (session_id IS NOT NULL);



CREATE INDEX idx_analysis_events_tenant_type ON public.analysis_events USING btree (tenant_id, type, occurred_at DESC);



CREATE INDEX idx_analysis_events_unprocessed ON public.analysis_events USING btree (occurred_at) WHERE (processed_at IS NULL);



CREATE INDEX idx_applications_tenant_code ON public.applications USING btree (tenant_id, code) WHERE (enabled = true);



CREATE INDEX idx_approval_queue_expires ON public.approval_queue USING btree (expires_at) WHERE (status = 'pending'::text);



CREATE INDEX idx_approval_queue_session ON public.approval_queue USING btree (session_id, created_at DESC);



CREATE INDEX idx_approval_queue_tenant_pending ON public.approval_queue USING btree (tenant_id, created_at DESC) WHERE (status = 'pending'::text);



CREATE INDEX idx_armor_judgments_request ON public.armor_judgments USING btree (request_id);



CREATE INDEX idx_armor_judgments_stats ON public.armor_judgments USING btree (check_type, decision);



CREATE INDEX idx_armor_judgments_tenant_time ON public.armor_judgments USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_asset_rel_dst ON public.asset_relationships USING btree (dst_kind, dst_ref_id);



CREATE INDEX idx_asset_rel_src ON public.asset_relationships USING btree (src_kind, src_ref_id);



CREATE INDEX idx_assets_tags ON public.assets USING gin (tags jsonb_path_ops);



CREATE INDEX idx_assets_tenant_kind ON public.assets USING btree (tenant_id, kind);



CREATE INDEX idx_attachments_hash ON public.attachments USING btree (content_hash, tenant_id);



CREATE INDEX idx_attachments_request ON public.attachments USING btree (request_id);



CREATE INDEX idx_attachments_tenant_created ON public.attachments USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_billing_orders_status ON public.billing_orders USING btree (status, created_at DESC);



CREATE INDEX idx_billing_orders_tenant ON public.billing_orders USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_call_history_cred_time ON public.credential_model_call_history USING btree (credential_id, window_start DESC);



CREATE INDEX idx_call_history_errors ON public.credential_model_call_history USING btree (credential_id, raw_model, window_start DESC) WHERE ((error_rate_limit_count > 0) OR (error_concurrent_count > 0));



CREATE INDEX idx_call_history_model_time ON public.credential_model_call_history USING btree (raw_model, window_start DESC);



CREATE INDEX idx_cmb_credential_provider_model ON public.credential_model_bindings USING btree (credential_id, provider_model_id);



CREATE INDEX idx_cmb_pending_verification ON public.credential_model_bindings USING btree (credential_id) WHERE (pending_verification = true);



CREATE INDEX idx_cmb_unavailable_recover_at ON public.credential_model_bindings USING btree (unavailable_recover_at) WHERE (available = false);



CREATE INDEX idx_credential_probes_cred_time ON public.credential_probes USING btree (credential_id, created_at DESC);



CREATE INDEX idx_credential_probes_success ON public.credential_probes USING btree (success, created_at DESC);



CREATE INDEX idx_credentials_auto_limit ON public.credentials USING btree (concurrency_limit_auto) WHERE (concurrency_limit_auto IS NOT NULL);



CREATE INDEX idx_credit_ledger_tenant_ts ON public.credit_ledger_old USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_detections_request ON public.prompt_injection_detections USING btree (request_id);



CREATE INDEX idx_detections_risk ON public.prompt_injection_detections USING btree (tenant_id, risk_level) WHERE (blocked = true);



CREATE INDEX idx_detections_session ON public.prompt_injection_detections USING btree (session_key);



CREATE INDEX idx_detections_tenant_time ON public.prompt_injection_detections USING btree (tenant_id, detected_at DESC);



CREATE INDEX idx_goal_sessions_session ON public.goal_sessions USING btree (session_id);



CREATE INDEX idx_goal_sessions_state ON public.goal_sessions USING btree (state, last_activity_at);



CREATE INDEX idx_goal_sessions_tenant ON public.goal_sessions USING btree (tenant_id, state);



CREATE INDEX idx_handoff_logs_session ON public.handoff_logs USING btree (session_id, created_at DESC);



CREATE INDEX idx_handoff_logs_tenant ON public.handoff_logs USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_intent_aggregates_tenant_updated ON public.intent_aggregates USING btree (tenant_id, last_updated DESC);



CREATE INDEX idx_model_aliases_lower_raw_name_status ON public.model_aliases USING btree (lower(raw_name), status) WHERE (status = 'active'::text);



CREATE INDEX idx_model_probe_state_retry ON public.model_probe_state USING btree (state, next_retry_at) WHERE (state = 'recovering'::text);



CREATE INDEX idx_models_canonical_released ON public.models_canonical USING btree (released_at DESC NULLS LAST);



CREATE INDEX idx_models_canonical_strengths ON public.models_canonical USING gin (strengths);



CREATE INDEX idx_models_canonical_version_rank ON public.models_canonical USING btree (version_rank);



CREATE INDEX idx_mps_due ON public.model_probe_state USING btree (next_retry_at) WHERE (state = ANY (ARRAY['unknown'::text, 'recovering'::text]));



CREATE INDEX idx_mps_priority_next_retry ON public.model_probe_state USING btree (probe_priority, next_retry_at) WHERE (state = ANY (ARRAY['suspicious'::text, 'failing'::text, 'recovering'::text]));



CREATE INDEX idx_mps_probing ON public.model_probe_state USING btree (probing_started_at) WHERE (state = 'probing'::text);



CREATE INDEX idx_mps_success_rate ON public.model_probe_state USING btree (success_rate_7d);



CREATE INDEX idx_mps_suspicious_expired ON public.model_probe_state USING btree (state_expires_at) WHERE ((state = ANY (ARRAY['available'::text, 'unavailable'::text])) AND (state_expires_at IS NOT NULL));



CREATE INDEX idx_mps_suspicious_pending ON public.model_probe_state USING btree (marked_suspicious_at, next_retry_at) WHERE (state = 'suspicious'::text);



CREATE INDEX idx_output_audit_issue ON public.output_compliance_audit USING btree (tenant_id, issue_type, severity DESC);



CREATE INDEX idx_output_audit_request ON public.output_compliance_audit USING btree (request_id);



CREATE INDEX idx_output_audit_session ON public.output_compliance_audit USING btree (session_key);



CREATE INDEX idx_output_audit_tenant_time ON public.output_compliance_audit USING btree (tenant_id, detected_at DESC);



CREATE INDEX idx_passive_probe_reviewing ON public.passive_probe_state USING btree (in_reviewing, reviewing_until) WHERE (in_reviewing = true);



CREATE INDEX idx_provider_models_canonical_id ON public.provider_models USING btree (canonical_id);



CREATE INDEX idx_provider_models_lower_raw_model_name ON public.provider_models USING btree (lower(raw_model_name));



CREATE INDEX idx_provider_models_lower_standardized_name ON public.provider_models USING btree (lower(standardized_name));



CREATE INDEX idx_provider_quality_rollup_bucket ON public.provider_quality_rollup USING btree (bucket_start DESC);



CREATE INDEX idx_provider_settings_key ON public.provider_settings USING btree (setting_key) WHERE (enabled = true);



CREATE INDEX idx_provider_settings_provider ON public.provider_settings USING btree (provider_id) WHERE (enabled = true);



CREATE INDEX idx_request_logs_client_model ON ONLY public.request_logs USING btree (client_model);



CREATE INDEX idx_request_logs_client_model_hash ON ONLY public.request_logs USING hash (client_model);



CREATE INDEX idx_request_logs_client_model_lower ON ONLY public.request_logs USING btree (lower(client_model));



CREATE INDEX idx_request_logs_client_model_prefix ON ONLY public.request_logs USING btree (client_model text_pattern_ops);



CREATE INDEX idx_request_logs_client_request_id ON ONLY public.request_logs USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);



CREATE INDEX idx_request_logs_credits_charged ON ONLY public.request_logs USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));



CREATE INDEX idx_request_logs_gw_session_ts ON ONLY public.request_logs USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));



CREATE INDEX idx_request_logs_gw_task_ts ON ONLY public.request_logs USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX idx_request_logs_has_attachments ON ONLY public.request_logs USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);



CREATE INDEX idx_request_logs_outbound_msg_count ON ONLY public.request_logs USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));



CREATE INDEX idx_request_logs_parent_ts ON ONLY public.request_logs USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);



CREATE INDEX idx_request_logs_provider_model ON ONLY public.request_logs USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);



CREATE INDEX idx_request_logs_provider_quality ON ONLY public.request_logs USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);



CREATE INDEX idx_request_logs_provider_tool_calls ON ONLY public.request_logs USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));



CREATE INDEX idx_request_logs_quality_flags ON ONLY public.request_logs USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);



CREATE UNIQUE INDEX idx_request_logs_request_id_ts_unique ON ONLY public.request_logs USING btree (request_id, ts);



CREATE INDEX idx_request_logs_session_outbound ON ONLY public.request_logs USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));



CREATE INDEX idx_request_logs_status_ts ON ONLY public.request_logs USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));



CREATE INDEX idx_request_logs_tenant_task_ts ON ONLY public.request_logs USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX idx_request_logs_tool_calls ON ONLY public.request_logs USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));



CREATE INDEX idx_request_logs_ts_desc ON ONLY public.request_logs USING btree (ts DESC);



CREATE INDEX idx_request_logs_upstream_finish_reason ON ONLY public.request_logs USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));



CREATE INDEX idx_request_logs_upstream_status ON ONLY public.request_logs USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);



CREATE INDEX idx_request_logs_work_type ON ONLY public.request_logs USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



CREATE INDEX idx_response_format_anomalies_detected_at ON public.response_format_anomalies USING btree (detected_at DESC);



CREATE INDEX idx_response_format_anomalies_provider ON public.response_format_anomalies USING btree (provider_code, client_model) WHERE (provider_code IS NOT NULL);



CREATE INDEX idx_response_format_anomalies_request_id ON public.response_format_anomalies USING btree (request_id);



CREATE INDEX idx_response_format_anomalies_type ON public.response_format_anomalies USING btree (anomaly_type, detected_at DESC);



CREATE INDEX idx_response_format_anomalies_unresolved ON public.response_format_anomalies USING btree (detected_at DESC) WHERE (NOT resolved);



CREATE INDEX idx_routing_decision_log_part_credential ON ONLY public.routing_decision_log USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);



CREATE INDEX idx_routing_decision_log_part_model ON ONLY public.routing_decision_log USING btree (model, ts DESC);



CREATE INDEX idx_routing_decision_log_part_request_id ON ONLY public.routing_decision_log USING btree (request_id);



CREATE INDEX idx_routing_decision_log_part_success ON ONLY public.routing_decision_log USING btree (success, ts DESC);



CREATE INDEX idx_routing_decision_log_part_tenant_ts ON ONLY public.routing_decision_log USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);



CREATE INDEX idx_routing_decision_log_part_ts ON ONLY public.routing_decision_log USING btree (ts DESC);



CREATE INDEX idx_routing_overrides_audit_actor_ts ON public.routing_overrides_audit USING btree (actor, ts DESC) WHERE (actor IS NOT NULL);



CREATE INDEX idx_routing_overrides_audit_override_ts ON public.routing_overrides_audit USING btree (override_id, ts DESC) WHERE (override_id IS NOT NULL);



CREATE INDEX idx_routing_overrides_audit_ts ON public.routing_overrides_audit USING btree (ts DESC);



CREATE INDEX idx_routing_overrides_expires ON public.routing_overrides USING btree (expires_at) WHERE (expires_at IS NOT NULL);



CREATE INDEX idx_routing_overrides_task_profile ON public.routing_overrides USING btree (task_type, profile);



CREATE UNIQUE INDEX idx_routing_overrides_unique ON public.routing_overrides USING btree (task_type, profile, COALESCE(model_chosen, ''::text), mode);



CREATE INDEX idx_session_audit_records_session ON public.session_audit_records USING btree (session_id, created_at DESC);



CREATE INDEX idx_session_audit_records_status ON public.session_audit_records USING btree (status, created_at DESC) WHERE (status = 'need_approval'::text);



CREATE INDEX idx_session_audit_records_tenant_created ON public.session_audit_records USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_session_memora_extraction_at ON public.session_memora_extraction_log USING btree (extracted_at DESC);



CREATE INDEX idx_session_summaries_compliance ON public.session_summaries USING btree (tenant_id, compliance_status) WHERE ((compliance_status)::text <> 'compliant'::text);



CREATE INDEX idx_session_summaries_cost ON public.session_summaries USING btree (tenant_id, total_cost_usd DESC);



CREATE INDEX idx_session_summaries_intent ON public.session_summaries USING btree (tenant_id, user_intent) WHERE (user_intent IS NOT NULL);



CREATE INDEX idx_session_summaries_models ON public.session_summaries USING gin (models_used);



CREATE INDEX idx_session_summaries_quality ON public.session_summaries USING btree (quality_score DESC) WHERE (quality_score IS NOT NULL);



CREATE INDEX idx_session_summaries_tenant_time ON public.session_summaries USING btree (tenant_id, last_request_at DESC);



CREATE INDEX idx_session_summaries_topics ON public.session_summaries USING gin (key_topics);



CREATE INDEX idx_session_titles_generated_at ON public.session_titles USING btree (generated_at DESC);



CREATE INDEX idx_settings_audit_created ON public.settings_audit USING btree (created_at);



CREATE INDEX idx_settings_audit_key_time ON public.settings_audit USING btree (setting_key, created_at DESC);



CREATE INDEX idx_settings_audit_operator ON public.settings_audit USING btree (operator_user, created_at DESC);



CREATE INDEX idx_settings_audit_tenant_time ON public.settings_audit USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_settings_kv_category ON public.settings_kv USING btree (category);



CREATE INDEX idx_settings_kv_scope ON public.settings_kv USING btree (scope);



CREATE INDEX idx_settings_kv_updated ON public.settings_kv USING btree (updated_at DESC);



CREATE UNIQUE INDEX idx_sticky_sessions_sticky_key_unique ON public.sticky_sessions USING btree (sticky_key);



CREATE INDEX idx_tenant_settings_kv_category ON public.tenant_settings_kv USING btree (category);



CREATE INDEX idx_tenant_settings_kv_tenant ON public.tenant_settings_kv USING btree (tenant_id);



CREATE INDEX idx_tenant_subscriptions_tenant ON public.tenant_subscriptions USING btree (tenant_id, status);



CREATE INDEX idx_tenant_tool_policies_enabled ON public.tenant_tool_policies USING btree (enabled);



CREATE INDEX idx_tenant_tool_policies_tenant ON public.tenant_tool_policies USING btree (tenant_id) WHERE (enabled = true);



CREATE INDEX idx_tenants_name ON public.tenants USING btree (name);



CREATE INDEX idx_tenants_status ON public.tenants USING btree (status);



CREATE INDEX idx_tmp_audit_tenant_ts ON public.tenant_model_policies_audit USING btree (tenant_id, ts DESC);



CREATE INDEX idx_tmp_audit_ts ON public.tenant_model_policies_audit USING btree (ts DESC);



CREATE INDEX idx_tmp_canonical ON public.tenant_model_policies USING btree (canonical_name);



CREATE INDEX idx_tmp_tenant_active ON public.tenant_model_policies USING btree (tenant_id) WHERE (deleted_at IS NULL);



CREATE INDEX idx_tool_categories_order ON public.tool_categories USING btree (display_order) WHERE (enabled = true);



CREATE INDEX idx_tool_registry_category ON public.tool_registry USING btree (category) WHERE (enabled = true);



CREATE INDEX idx_tool_registry_deprecation ON public.tool_registry USING btree (deprecation_date) WHERE (deprecation_date IS NOT NULL);



CREATE INDEX idx_tool_registry_name ON public.tool_registry USING btree (tool_name) WHERE (enabled = true);



CREATE INDEX idx_tool_registry_tenant_tool ON public.tool_registry USING btree (tenant_id, tool_id, version DESC);



CREATE UNIQUE INDEX idx_tool_registry_unique_version ON public.tool_registry USING btree (tenant_id, tool_id, version);



CREATE INDEX idx_tool_stats_part_created ON ONLY public.tool_usage_stats USING btree (created_at);



CREATE INDEX idx_tool_stats_part_date ON ONLY public.tool_usage_stats USING btree (usage_date);



CREATE INDEX idx_tool_stats_part_tenant ON ONLY public.tool_usage_stats USING btree (tenant_id, usage_date);



CREATE INDEX idx_tool_stats_part_tool ON ONLY public.tool_usage_stats USING btree (tool_id, usage_date);



CREATE INDEX idx_tool_usage_stats_date ON public.tool_usage_stats_old USING btree (usage_date DESC);



CREATE INDEX idx_tool_usage_stats_tenant_id ON public.tool_usage_stats_old USING btree (tenant_id);



CREATE INDEX idx_tool_usage_stats_tool_id ON public.tool_usage_stats_old USING btree (tool_id);



CREATE INDEX idx_tool_usage_stats_tool_tenant ON public.tool_usage_stats_old USING btree (tool_id, tenant_id, usage_date DESC);



CREATE INDEX idx_tuning_proposals_cat ON public.tuning_proposals USING btree (category, task_type) WHERE (status = 'pending'::text);



CREATE INDEX idx_tuning_proposals_created ON public.tuning_proposals USING btree (created_at) WHERE (status = 'pending'::text);



CREATE INDEX idx_tuning_proposals_status ON public.tuning_proposals USING btree (status, ts DESC);



CREATE UNIQUE INDEX idx_tuning_signals_5m_pk ON public.tuning_signals_5m USING btree (bucket, task_type, classifier);



CREATE INDEX idx_tuning_signals_5m_task_ts ON public.tuning_signals_5m USING btree (task_type, classifier, bucket DESC);



CREATE UNIQUE INDEX idx_tuning_signals_daily_pk ON public.tuning_signals_daily USING btree (bucket, task_type, classifier);



CREATE INDEX idx_tuning_signals_daily_task_ts ON public.tuning_signals_daily USING btree (task_type, classifier, bucket DESC);



CREATE INDEX idx_tuning_signals_lowq ON public.tuning_signals USING btree (task_type, ts DESC) WHERE ((quality_score < 0.5) AND (classifier = 'heuristic'::text));



CREATE INDEX idx_tuning_signals_session ON public.tuning_signals USING btree (session_id, ts DESC) WHERE (session_id IS NOT NULL);



CREATE INDEX idx_tuning_signals_strategy_task ON public.tuning_signals USING btree (strategy, task_type, ts DESC) WHERE (task_type IS NOT NULL);



CREATE INDEX idx_tuning_signals_strategy_ts ON public.tuning_signals USING btree (strategy, ts DESC);



CREATE INDEX idx_tuning_signals_task_ts ON public.tuning_signals USING btree (task_type, ts DESC);



CREATE INDEX idx_usage_ledger_part_request_id ON ONLY public.usage_ledger USING btree (request_id);



CREATE INDEX idx_usage_ledger_part_tenant ON ONLY public.usage_ledger USING btree (tenant_id, ts);



CREATE INDEX idx_usage_ledger_part_ts ON ONLY public.usage_ledger USING btree (ts);



CREATE INDEX idx_users_tenant ON public.users USING btree (tenant_id);



CREATE INDEX idx_users_username ON public.users USING btree (username);



CREATE INDEX idx_wal_session ON ONLY public.request_wal USING btree (gw_session_id, created_at);



CREATE INDEX idx_wal_status_stage ON ONLY public.request_wal USING btree (status, stage);



CREATE INDEX idx_wal_tenant_created ON ONLY public.request_wal USING btree (tenant_id, created_at DESC);



CREATE INDEX idx_work_type_config_category ON public.work_type_config USING btree (category, sort_order);



CREATE INDEX idx_work_type_config_l1 ON public.work_type_config USING btree (l1_task_type);



CREATE INDEX idx_wtmr_tier ON public.work_type_model_route USING btree (work_type_key, tier, weight DESC);



CREATE INDEX idx_wtmr_work_type ON public.work_type_model_route USING btree (work_type_key);



CREATE INDEX request_logs_2026_06_client_model_idx ON public.request_logs_2026_06 USING btree (client_model);



CREATE INDEX request_logs_2026_06_client_model_idx1 ON public.request_logs_2026_06 USING btree (client_model text_pattern_ops);



CREATE INDEX request_logs_2026_06_client_model_idx2 ON public.request_logs_2026_06 USING hash (client_model);



CREATE INDEX request_logs_2026_06_client_request_id_ts_idx ON public.request_logs_2026_06 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_06_gw_session_id_ts_idx ON public.request_logs_2026_06 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));



CREATE INDEX request_logs_2026_06_gw_session_id_ts_idx1 ON public.request_logs_2026_06 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));



CREATE INDEX request_logs_2026_06_gw_task_id_ts_idx ON public.request_logs_2026_06 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_06_has_attachments_ts_idx ON public.request_logs_2026_06 USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);



CREATE INDEX request_logs_2026_06_lower_idx ON public.request_logs_2026_06 USING btree (lower(client_model));



CREATE INDEX request_logs_2026_06_parent_request_id_ts_idx ON public.request_logs_2026_06 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_06_provider_id_quality_score_ts_idx ON public.request_logs_2026_06 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);



CREATE INDEX request_logs_2026_06_provider_id_ts_idx ON public.request_logs_2026_06 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));



CREATE INDEX request_logs_2026_06_provider_model_ts_idx ON public.request_logs_2026_06 USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);



CREATE INDEX request_logs_2026_06_quality_flags_idx ON public.request_logs_2026_06 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);



CREATE UNIQUE INDEX request_logs_2026_06_request_id_ts_idx ON public.request_logs_2026_06 USING btree (request_id, ts);



CREATE INDEX request_logs_2026_06_request_status_ts_idx ON public.request_logs_2026_06 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));



CREATE INDEX request_logs_2026_06_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_06 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_06_tenant_id_ts_idx ON public.request_logs_2026_06 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));



CREATE INDEX request_logs_2026_06_tenant_id_ts_idx1 ON public.request_logs_2026_06 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));



CREATE INDEX request_logs_2026_06_tool_calls_idx ON public.request_logs_2026_06 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));



CREATE INDEX request_logs_2026_06_ts_idx ON public.request_logs_2026_06 USING btree (ts DESC);



CREATE INDEX request_logs_2026_06_upstream_finish_reason_ts_idx ON public.request_logs_2026_06 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));



CREATE INDEX request_logs_2026_06_upstream_status_code_ts_idx ON public.request_logs_2026_06 USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);



CREATE INDEX request_logs_2026_06_work_type_ts_idx ON public.request_logs_2026_06 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



CREATE INDEX request_logs_2026_07_client_model_idx ON public.request_logs_2026_07 USING btree (client_model);



CREATE INDEX request_logs_2026_07_client_model_idx1 ON public.request_logs_2026_07 USING btree (client_model text_pattern_ops);



CREATE INDEX request_logs_2026_07_client_model_idx2 ON public.request_logs_2026_07 USING hash (client_model);



CREATE INDEX request_logs_2026_07_client_request_id_ts_idx ON public.request_logs_2026_07 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_07_col_client_model_idx ON public.request_logs_2026_07_columnar_backup USING btree (client_model);



CREATE INDEX request_logs_2026_07_col_client_model_idx1 ON public.request_logs_2026_07_columnar_backup USING btree (client_model text_pattern_ops);



CREATE INDEX request_logs_2026_07_col_client_model_idx2 ON public.request_logs_2026_07_columnar_backup USING hash (client_model);



CREATE INDEX request_logs_2026_07_col_client_request_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_07_col_gw_session_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));



CREATE INDEX request_logs_2026_07_col_gw_session_id_ts_idx1 ON public.request_logs_2026_07_columnar_backup USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));



CREATE INDEX request_logs_2026_07_col_gw_task_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_07_col_has_attachments_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);



CREATE INDEX request_logs_2026_07_col_lower_idx ON public.request_logs_2026_07_columnar_backup USING btree (lower(client_model));



CREATE INDEX request_logs_2026_07_col_parent_request_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_07_col_provider_id_quality_score_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);



CREATE INDEX request_logs_2026_07_col_provider_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));



CREATE INDEX request_logs_2026_07_col_provider_model_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);



CREATE INDEX request_logs_2026_07_col_quality_flags_idx ON public.request_logs_2026_07_columnar_backup USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);



CREATE UNIQUE INDEX request_logs_2026_07_col_request_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (request_id, ts);



CREATE INDEX request_logs_2026_07_col_request_status_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));



CREATE INDEX request_logs_2026_07_col_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_07_col_tenant_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));



CREATE INDEX request_logs_2026_07_col_tenant_id_ts_idx1 ON public.request_logs_2026_07_columnar_backup USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));



CREATE INDEX request_logs_2026_07_col_tool_calls_idx ON public.request_logs_2026_07_columnar_backup USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));



CREATE INDEX request_logs_2026_07_col_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (ts DESC);



CREATE INDEX request_logs_2026_07_col_upstream_finish_reason_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));



CREATE INDEX request_logs_2026_07_col_upstream_status_code_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);



CREATE INDEX request_logs_2026_07_col_work_type_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



CREATE INDEX request_logs_2026_07_gw_session_id_ts_idx ON public.request_logs_2026_07 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));



CREATE INDEX request_logs_2026_07_gw_session_id_ts_idx1 ON public.request_logs_2026_07 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));



CREATE INDEX request_logs_2026_07_gw_task_id_ts_idx ON public.request_logs_2026_07 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_07_has_attachments_ts_idx ON public.request_logs_2026_07 USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);



CREATE INDEX request_logs_2026_07_lower_idx ON public.request_logs_2026_07 USING btree (lower(client_model));



CREATE INDEX request_logs_2026_07_parent_request_id_ts_idx ON public.request_logs_2026_07 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_07_provider_id_quality_score_ts_idx ON public.request_logs_2026_07 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);



CREATE INDEX request_logs_2026_07_provider_id_ts_idx ON public.request_logs_2026_07 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));



CREATE INDEX request_logs_2026_07_provider_model_ts_idx ON public.request_logs_2026_07 USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);



CREATE INDEX request_logs_2026_07_quality_flags_idx ON public.request_logs_2026_07 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);



CREATE UNIQUE INDEX request_logs_2026_07_request_id_ts_idx ON public.request_logs_2026_07 USING btree (request_id, ts);



CREATE INDEX request_logs_2026_07_request_status_ts_idx ON public.request_logs_2026_07 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));



CREATE INDEX request_logs_2026_07_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_07 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_07_tenant_id_ts_idx ON public.request_logs_2026_07 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));



CREATE INDEX request_logs_2026_07_tenant_id_ts_idx1 ON public.request_logs_2026_07 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));



CREATE INDEX request_logs_2026_07_tool_calls_idx ON public.request_logs_2026_07 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));



CREATE INDEX request_logs_2026_07_ts_idx ON public.request_logs_2026_07 USING btree (ts DESC);



CREATE INDEX request_logs_2026_07_upstream_finish_reason_ts_idx ON public.request_logs_2026_07 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));



CREATE INDEX request_logs_2026_07_upstream_status_code_ts_idx ON public.request_logs_2026_07 USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);



CREATE INDEX request_logs_2026_07_work_type_ts_idx ON public.request_logs_2026_07 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



CREATE INDEX request_logs_2026_08_heap_client_model_idx ON public.request_logs_2026_08 USING btree (client_model);



CREATE INDEX request_logs_2026_08_heap_client_model_idx1 ON public.request_logs_2026_08 USING btree (client_model text_pattern_ops);



CREATE INDEX request_logs_2026_08_heap_client_model_idx2 ON public.request_logs_2026_08 USING hash (client_model);



CREATE INDEX request_logs_2026_08_heap_client_request_id_ts_idx ON public.request_logs_2026_08 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_08_heap_gw_session_id_ts_idx ON public.request_logs_2026_08 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));



CREATE INDEX request_logs_2026_08_heap_gw_session_id_ts_idx1 ON public.request_logs_2026_08 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));



CREATE INDEX request_logs_2026_08_heap_gw_task_id_ts_idx ON public.request_logs_2026_08 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_08_heap_has_attachments_ts_idx ON public.request_logs_2026_08 USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);



CREATE INDEX request_logs_2026_08_heap_lower_idx ON public.request_logs_2026_08 USING btree (lower(client_model));



CREATE INDEX request_logs_2026_08_heap_parent_request_id_ts_idx ON public.request_logs_2026_08 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);



CREATE INDEX request_logs_2026_08_heap_provider_id_quality_score_ts_idx ON public.request_logs_2026_08 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);



CREATE INDEX request_logs_2026_08_heap_provider_id_ts_idx ON public.request_logs_2026_08 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));



CREATE INDEX request_logs_2026_08_heap_provider_model_ts_idx ON public.request_logs_2026_08 USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);



CREATE INDEX request_logs_2026_08_heap_quality_flags_idx ON public.request_logs_2026_08 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);



CREATE UNIQUE INDEX request_logs_2026_08_heap_request_id_ts_idx ON public.request_logs_2026_08 USING btree (request_id, ts);



CREATE INDEX request_logs_2026_08_heap_request_status_ts_idx ON public.request_logs_2026_08 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));



CREATE INDEX request_logs_2026_08_heap_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_08 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_2026_08_heap_tenant_id_ts_idx ON public.request_logs_2026_08 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));



CREATE INDEX request_logs_2026_08_heap_tenant_id_ts_idx1 ON public.request_logs_2026_08 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));



CREATE INDEX request_logs_2026_08_heap_tool_calls_idx ON public.request_logs_2026_08 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));



CREATE INDEX request_logs_2026_08_heap_ts_idx ON public.request_logs_2026_08 USING btree (ts DESC);



CREATE INDEX request_logs_2026_08_heap_upstream_finish_reason_ts_idx ON public.request_logs_2026_08 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));



CREATE INDEX request_logs_2026_08_heap_upstream_status_code_ts_idx ON public.request_logs_2026_08 USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);



CREATE INDEX request_logs_2026_08_heap_work_type_ts_idx ON public.request_logs_2026_08 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



CREATE INDEX request_logs_default_client_model_idx4 ON public.request_logs_default USING btree (client_model);



CREATE INDEX request_logs_default_client_model_idx5 ON public.request_logs_default USING btree (client_model text_pattern_ops);



CREATE INDEX request_logs_default_client_model_idx6 ON public.request_logs_default USING hash (client_model);



CREATE INDEX request_logs_default_client_request_id_ts_idx1 ON public.request_logs_default USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);



CREATE INDEX request_logs_default_gw_session_id_ts_idx2 ON public.request_logs_default USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));



CREATE INDEX request_logs_default_gw_session_id_ts_idx3 ON public.request_logs_default USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));



CREATE INDEX request_logs_default_gw_task_id_ts_idx1 ON public.request_logs_default USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_default_has_attachments_ts_idx ON public.request_logs_default USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);



CREATE INDEX request_logs_default_lower_idx1 ON public.request_logs_default USING btree (lower(client_model));



CREATE INDEX request_logs_default_parent_request_id_ts_idx1 ON public.request_logs_default USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);



CREATE INDEX request_logs_default_provider_id_quality_score_ts_idx1 ON public.request_logs_default USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);



CREATE INDEX request_logs_default_provider_id_ts_idx1 ON public.request_logs_default USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));



CREATE INDEX request_logs_default_provider_model_ts_idx ON public.request_logs_default USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);



CREATE INDEX request_logs_default_quality_flags_idx1 ON public.request_logs_default USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);



CREATE UNIQUE INDEX request_logs_default_request_id_ts_idx1 ON public.request_logs_default USING btree (request_id, ts);



CREATE INDEX request_logs_default_request_status_ts_idx1 ON public.request_logs_default USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));



CREATE INDEX request_logs_default_tenant_id_gw_task_id_ts_idx1 ON public.request_logs_default USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));



CREATE INDEX request_logs_default_tenant_id_ts_idx2 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));



CREATE INDEX request_logs_default_tenant_id_ts_idx3 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));



CREATE INDEX request_logs_default_tool_calls_idx1 ON public.request_logs_default USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));



CREATE INDEX request_logs_default_ts_idx ON public.request_logs_default USING btree (ts DESC);



CREATE INDEX request_logs_default_upstream_finish_reason_ts_idx1 ON public.request_logs_default USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));



CREATE INDEX request_logs_default_upstream_status_code_ts_idx ON public.request_logs_default USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);



CREATE INDEX request_logs_default_work_type_ts_idx1 ON public.request_logs_default USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



CREATE INDEX request_wal_2026_06_col_gw_session_id_created_at_idx ON public.request_wal_2026_06 USING btree (gw_session_id, created_at);



CREATE INDEX request_wal_2026_06_col_status_stage_idx ON public.request_wal_2026_06 USING btree (status, stage);



CREATE INDEX request_wal_2026_06_col_tenant_id_created_at_idx ON public.request_wal_2026_06 USING btree (tenant_id, created_at DESC);



CREATE INDEX request_wal_2026_07_col_gw_session_id_created_at_idx ON public.request_wal_2026_07_columnar USING btree (gw_session_id, created_at);



CREATE INDEX request_wal_2026_07_col_status_stage_idx ON public.request_wal_2026_07_columnar USING btree (status, stage);



CREATE INDEX request_wal_2026_07_col_tenant_id_created_at_idx ON public.request_wal_2026_07_columnar USING btree (tenant_id, created_at DESC);



CREATE INDEX request_wal_2026_07_gw_session_id_created_at_idx ON public.request_wal_2026_07 USING btree (gw_session_id, created_at);



CREATE INDEX request_wal_2026_07_status_stage_idx ON public.request_wal_2026_07 USING btree (status, stage);



CREATE INDEX request_wal_2026_07_tenant_id_created_at_idx ON public.request_wal_2026_07 USING btree (tenant_id, created_at DESC);



CREATE INDEX request_wal_2026_08_gw_session_id_created_at_idx ON public.request_wal_2026_08 USING btree (gw_session_id, created_at);



CREATE INDEX request_wal_2026_08_status_stage_idx ON public.request_wal_2026_08 USING btree (status, stage);



CREATE INDEX request_wal_2026_08_tenant_id_created_at_idx ON public.request_wal_2026_08 USING btree (tenant_id, created_at DESC);



CREATE INDEX request_wal_default_gw_session_id_created_at_idx ON public.request_wal_default USING btree (gw_session_id, created_at);



CREATE INDEX request_wal_default_status_stage_idx ON public.request_wal_default USING btree (status, stage);



CREATE INDEX request_wal_default_tenant_id_created_at_idx ON public.request_wal_default USING btree (tenant_id, created_at DESC);



CREATE INDEX routing_decision_log_2026_07_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);



CREATE INDEX routing_decision_log_2026_07_model_ts_idx ON public.routing_decision_log_2026_07 USING btree (model, ts DESC);



CREATE INDEX routing_decision_log_2026_07_request_id_idx ON public.routing_decision_log_2026_07 USING btree (request_id);



CREATE INDEX routing_decision_log_2026_07_success_ts_idx ON public.routing_decision_log_2026_07 USING btree (success, ts DESC);



CREATE INDEX routing_decision_log_2026_07_tenant_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);



CREATE INDEX routing_decision_log_2026_07_ts_idx ON public.routing_decision_log_2026_07 USING btree (ts DESC);



CREATE INDEX routing_decision_log_2026_08_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_08 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);



CREATE INDEX routing_decision_log_2026_08_model_ts_idx ON public.routing_decision_log_2026_08 USING btree (model, ts DESC);



CREATE INDEX routing_decision_log_2026_08_request_id_idx ON public.routing_decision_log_2026_08 USING btree (request_id);



CREATE INDEX routing_decision_log_2026_08_success_ts_idx ON public.routing_decision_log_2026_08 USING btree (success, ts DESC);



CREATE INDEX routing_decision_log_2026_08_tenant_id_ts_idx ON public.routing_decision_log_2026_08 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);



CREATE INDEX routing_decision_log_2026_08_ts_idx ON public.routing_decision_log_2026_08 USING btree (ts DESC);



CREATE INDEX routing_decision_log_default_chosen_credential_id_ts_idx ON public.routing_decision_log_default USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);



CREATE INDEX routing_decision_log_default_model_ts_idx ON public.routing_decision_log_default USING btree (model, ts DESC);



CREATE INDEX routing_decision_log_default_request_id_idx ON public.routing_decision_log_default USING btree (request_id);



CREATE INDEX routing_decision_log_default_success_ts_idx ON public.routing_decision_log_default USING btree (success, ts DESC);



CREATE INDEX routing_decision_log_default_tenant_id_ts_idx ON public.routing_decision_log_default USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);



CREATE INDEX routing_decision_log_default_ts_idx ON public.routing_decision_log_default USING btree (ts DESC);



CREATE INDEX tool_usage_stats_2026_06_created_at_idx ON public.tool_usage_stats_2026_06 USING btree (created_at);



CREATE INDEX tool_usage_stats_2026_06_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (tenant_id, usage_date);



CREATE INDEX tool_usage_stats_2026_06_tool_id_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (tool_id, usage_date);



CREATE INDEX tool_usage_stats_2026_06_usage_date_idx ON public.tool_usage_stats_2026_06 USING btree (usage_date);



CREATE INDEX tool_usage_stats_2026_07_created_at_idx ON public.tool_usage_stats_2026_07 USING btree (created_at);



CREATE INDEX tool_usage_stats_2026_07_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (tenant_id, usage_date);



CREATE INDEX tool_usage_stats_2026_07_tool_id_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (tool_id, usage_date);



CREATE INDEX tool_usage_stats_2026_07_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (usage_date);



CREATE INDEX tool_usage_stats_2026_08_created_at_idx ON public.tool_usage_stats_2026_08 USING btree (created_at);



CREATE INDEX tool_usage_stats_2026_08_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tenant_id, usage_date);



CREATE INDEX tool_usage_stats_2026_08_tool_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tool_id, usage_date);



CREATE INDEX tool_usage_stats_2026_08_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (usage_date);



CREATE INDEX usage_ledger_2026_06_col_request_id_idx ON public.usage_ledger_2026_06 USING btree (request_id);



CREATE INDEX usage_ledger_2026_06_col_tenant_id_ts_idx ON public.usage_ledger_2026_06 USING btree (tenant_id, ts);



CREATE INDEX usage_ledger_2026_06_col_ts_idx ON public.usage_ledger_2026_06 USING btree (ts);



CREATE INDEX usage_ledger_2026_07_col_request_id_idx ON public.usage_ledger_2026_07_columnar_backup USING btree (request_id);



CREATE INDEX usage_ledger_2026_07_col_tenant_id_ts_idx ON public.usage_ledger_2026_07_columnar_backup USING btree (tenant_id, ts);



CREATE INDEX usage_ledger_2026_07_col_ts_idx ON public.usage_ledger_2026_07_columnar_backup USING btree (ts);



CREATE INDEX usage_ledger_2026_07_request_id_idx ON public.usage_ledger_2026_07 USING btree (request_id);



CREATE INDEX usage_ledger_2026_07_tenant_id_ts_idx ON public.usage_ledger_2026_07 USING btree (tenant_id, ts);



CREATE INDEX usage_ledger_2026_07_ts_idx ON public.usage_ledger_2026_07 USING btree (ts);



CREATE INDEX usage_ledger_2026_08_heap_request_id_idx ON public.usage_ledger_2026_08 USING btree (request_id);



CREATE INDEX usage_ledger_2026_08_heap_tenant_id_ts_idx ON public.usage_ledger_2026_08 USING btree (tenant_id, ts);



CREATE INDEX usage_ledger_2026_08_heap_ts_idx ON public.usage_ledger_2026_08 USING btree (ts);



CREATE INDEX usage_ledger_default_request_id_idx ON public.usage_ledger_default USING btree (request_id);



CREATE INDEX usage_ledger_default_tenant_id_ts_idx ON public.usage_ledger_default USING btree (tenant_id, ts);



CREATE INDEX usage_ledger_default_ts_idx ON public.usage_ledger_default USING btree (ts);



ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_2026_0_bucket_credential_id_raw_mod_idx1;



ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_2026_0_bucket_credential_id_raw_mod_idx3;



ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_2026_0_bucket_credential_id_raw_mode_idx;



ALTER INDEX public.idx_cmi_archive_cred_model ATTACH PARTITION public.credential_model_index_archiv_credential_id_raw_model_bucke_idx;



ALTER INDEX public.idx_cmi_archive_bucket ATTACH PARTITION public.credential_model_index_archive_2026_08_bucket_idx;



ALTER INDEX public.idx_cmi_archive_canonical ATTACH PARTITION public.credential_model_index_archive_2026_08_canonical_id_bucket_idx;



ALTER INDEX public.credential_model_index_bucket_cred_model_key ATTACH PARTITION public.credential_model_index_defaul_bucket_credential_id_raw_mode_idx;



ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_06_created_at_idx;



ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_06_pkey;



ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_06_ref_type_ref_id_idx;



ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_06_tenant_id_created_at_idx;



ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_07_created_at_idx;



ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_07_pkey;



ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_07_ref_type_ref_id_idx;



ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_07_tenant_id_created_at_idx;



ALTER INDEX public.idx_credit_ledger_part_created ATTACH PARTITION public.credit_ledger_2026_08_created_at_idx;



ALTER INDEX public.credit_ledger_partitioned_pkey ATTACH PARTITION public.credit_ledger_2026_08_pkey;



ALTER INDEX public.idx_credit_ledger_part_ref ATTACH PARTITION public.credit_ledger_2026_08_ref_type_ref_id_idx;



ALTER INDEX public.idx_credit_ledger_part_tenant ATTACH PARTITION public.credit_ledger_2026_08_tenant_id_created_at_idx;



ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_2026_06_client_model_idx;



ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_2026_06_client_model_idx1;



ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_2026_06_client_model_idx2;



ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_2026_06_client_request_id_ts_idx;



ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_2026_06_gw_session_id_ts_idx;



ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_2026_06_gw_session_id_ts_idx1;



ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_2026_06_gw_task_id_ts_idx;



ALTER INDEX public.idx_request_logs_has_attachments ATTACH PARTITION public.request_logs_2026_06_has_attachments_ts_idx;



ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_2026_06_lower_idx;



ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_2026_06_parent_request_id_ts_idx;



ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_2026_06_provider_id_quality_score_ts_idx;



ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_2026_06_provider_id_ts_idx;



ALTER INDEX public.idx_request_logs_provider_model ATTACH PARTITION public.request_logs_2026_06_provider_model_ts_idx;



ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_2026_06_quality_flags_idx;



ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_2026_06_request_id_ts_idx;



ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_2026_06_request_status_ts_idx;



ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_2026_06_tenant_id_gw_task_id_ts_idx;



ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_2026_06_tenant_id_ts_idx;



ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_2026_06_tenant_id_ts_idx1;



ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_2026_06_tool_calls_idx;



ALTER INDEX public.idx_request_logs_ts_desc ATTACH PARTITION public.request_logs_2026_06_ts_idx;



ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_2026_06_upstream_finish_reason_ts_idx;



ALTER INDEX public.idx_request_logs_upstream_status ATTACH PARTITION public.request_logs_2026_06_upstream_status_code_ts_idx;



ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_2026_06_work_type_ts_idx;



ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_default_client_model_idx4;



ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_default_client_model_idx5;



ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_default_client_model_idx6;



ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_default_client_request_id_ts_idx1;



ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_default_gw_session_id_ts_idx2;



ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_default_gw_session_id_ts_idx3;



ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_default_gw_task_id_ts_idx1;



ALTER INDEX public.idx_request_logs_has_attachments ATTACH PARTITION public.request_logs_default_has_attachments_ts_idx;



ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_default_lower_idx1;



ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_default_parent_request_id_ts_idx1;



ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_default_provider_id_quality_score_ts_idx1;



ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_default_provider_id_ts_idx1;



ALTER INDEX public.idx_request_logs_provider_model ATTACH PARTITION public.request_logs_default_provider_model_ts_idx;



ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_default_quality_flags_idx1;



ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_default_request_id_ts_idx1;



ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_default_request_status_ts_idx1;



ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_default_tenant_id_gw_task_id_ts_idx1;



ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_default_tenant_id_ts_idx2;



ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_default_tenant_id_ts_idx3;



ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_default_tool_calls_idx1;



ALTER INDEX public.idx_request_logs_ts_desc ATTACH PARTITION public.request_logs_default_ts_idx;



ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_default_upstream_finish_reason_ts_idx1;



ALTER INDEX public.idx_request_logs_upstream_status ATTACH PARTITION public.request_logs_default_upstream_status_code_ts_idx;



ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_default_work_type_ts_idx1;



ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_06_col_gw_session_id_created_at_idx;



ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_06_col_pkey;



ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_06_col_status_stage_idx;



ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_06_col_tenant_id_created_at_idx;



ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_07_gw_session_id_created_at_idx;



ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_07_pkey;



ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_07_status_stage_idx;



ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_07_tenant_id_created_at_idx;



ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_08_gw_session_id_created_at_idx;



ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_08_pkey;



ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_08_status_stage_idx;



ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_08_tenant_id_created_at_idx;



ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_default_gw_session_id_created_at_idx;



ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_default_pkey;



ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_default_status_stage_idx;



ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_default_tenant_id_created_at_idx;



ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_07_chosen_credential_id_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_07_model_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_07_request_id_idx;



ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_07_success_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_07_tenant_id_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_07_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_08_chosen_credential_id_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_08_model_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_08_request_id_idx;



ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_08_success_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_08_tenant_id_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_08_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_default_chosen_credential_id_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_default_model_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_default_request_id_idx;



ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_default_success_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_default_tenant_id_ts_idx;



ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_default_ts_idx;



ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_06_created_at_idx;



ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_06_pkey;



ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_06_tenant_id_usage_date_idx;



ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_tenant_id_usage_date_creat_key;



ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_usage_date_idx;



ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_06_usage_date_idx;



ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_07_created_at_idx;



ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_07_pkey;



ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_07_tenant_id_usage_date_idx;



ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_07_tool_id_tenant_id_usage_date_creat_key;



ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_07_tool_id_usage_date_idx;



ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_07_usage_date_idx;



ALTER INDEX public.idx_tool_stats_part_created ATTACH PARTITION public.tool_usage_stats_2026_08_created_at_idx;



ALTER INDEX public.tool_usage_stats_partitioned_pkey ATTACH PARTITION public.tool_usage_stats_2026_08_pkey;



ALTER INDEX public.idx_tool_stats_part_tenant ATTACH PARTITION public.tool_usage_stats_2026_08_tenant_id_usage_date_idx;



ALTER INDEX public.tool_usage_stats_partitioned_tool_id_tenant_id_usage_date_c_key ATTACH PARTITION public.tool_usage_stats_2026_08_tool_id_tenant_id_usage_date_creat_key;



ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_08_tool_id_usage_date_idx;



ALTER INDEX public.idx_tool_stats_part_date ATTACH PARTITION public.tool_usage_stats_2026_08_usage_date_idx;



ALTER INDEX public.idx_usage_ledger_part_request_id ATTACH PARTITION public.usage_ledger_2026_06_col_request_id_idx;



ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_2026_06_col_request_id_ts_key;



ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_2026_06_col_tenant_id_ts_idx;



ALTER INDEX public.idx_usage_ledger_part_ts ATTACH PARTITION public.usage_ledger_2026_06_col_ts_idx;



ALTER INDEX public.idx_usage_ledger_part_request_id ATTACH PARTITION public.usage_ledger_default_request_id_idx;



ALTER INDEX public.usage_ledger_partitioned_request_id_ts_key ATTACH PARTITION public.usage_ledger_default_request_id_ts_key;



ALTER INDEX public.idx_usage_ledger_part_tenant ATTACH PARTITION public.usage_ledger_default_tenant_id_ts_idx;



ALTER INDEX public.idx_usage_ledger_part_ts ATTACH PARTITION public.usage_ledger_default_ts_idx;



CREATE TRIGGER cmb_protect_manual_disable BEFORE UPDATE ON public.credential_model_bindings FOR EACH ROW EXECUTE FUNCTION public.trg_cmb_protect_manual_disable();



CREATE TRIGGER model_offers_delete INSTEAD OF DELETE ON public.model_offers FOR EACH ROW EXECUTE FUNCTION public.model_offers_delete_trigger();



CREATE TRIGGER model_offers_insert INSTEAD OF INSERT ON public.model_offers FOR EACH ROW EXECUTE FUNCTION public.model_offers_insert_trigger();



CREATE TRIGGER model_offers_update INSTEAD OF UPDATE ON public.model_offers FOR EACH ROW EXECUTE FUNCTION public.model_offers_update_trigger();



CREATE TRIGGER routing_overrides_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.routing_overrides FOR EACH ROW EXECUTE FUNCTION public.routing_overrides_audit_fn();



CREATE TRIGGER session_audit_records_updated_at BEFORE UPDATE ON public.session_audit_records FOR EACH ROW EXECUTE FUNCTION public.trg_session_audit_records_updated_at();



CREATE TRIGGER tenant_model_policies_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.tenant_model_policies FOR EACH ROW EXECUTE FUNCTION public.tenant_model_policies_audit_fn();



CREATE TRIGGER trg_auto_fp_slot_limit_insert BEFORE INSERT ON public.credentials FOR EACH ROW EXECUTE FUNCTION public.auto_set_fp_slot_limit();



CREATE TRIGGER trg_check_credential_dates BEFORE INSERT OR UPDATE ON public.credentials FOR EACH ROW EXECUTE FUNCTION public.check_credential_dates();



CREATE TRIGGER trg_key_applications_updated_at BEFORE UPDATE ON public.key_applications FOR EACH ROW EXECUTE FUNCTION public.key_applications_set_updated_at();



CREATE TRIGGER trg_notify_auto_route_apikeys AFTER UPDATE OF rate_limit_rpm, budget_usd, enabled, status ON public.api_keys FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();



CREATE TRIGGER trg_notify_auto_route_cmb AFTER INSERT OR DELETE OR UPDATE ON public.credential_model_bindings FOR EACH ROW EXECUTE FUNCTION public.notify_auto_route_refresh();



CREATE TRIGGER trg_notify_auto_route_creds AFTER UPDATE OF status, availability_state, quota_state, circuit_state, concurrency_limit, lifecycle_status, manual_disabled ON public.credentials FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();



CREATE TRIGGER trg_notify_auto_route_providers AFTER UPDATE OF enabled, manual_disabled ON public.providers FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();



CREATE TRIGGER trg_update_api_key_model_cost AFTER INSERT ON public.request_logs REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.update_api_key_model_cost_stmt();



CREATE TRIGGER trigger_provider_settings_updated_at BEFORE UPDATE ON public.provider_settings FOR EACH ROW EXECUTE FUNCTION public.update_provider_settings_updated_at();



ALTER TABLE ONLY public.credential_probe_configs
    ADD CONSTRAINT credential_probe_configs_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.credentials(id);



ALTER TABLE ONLY public.credential_probes
    ADD CONSTRAINT credential_probes_credential_id_fkey FOREIGN KEY (credential_id) REFERENCES public.credentials(id);



ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT fk_agent_rel_dst FOREIGN KEY (dst_agent_id) REFERENCES public.agents(id) ON DELETE CASCADE;



ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT fk_agent_rel_src FOREIGN KEY (src_agent_id) REFERENCES public.agents(id) ON DELETE CASCADE;



ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT fk_asset_rel_dst FOREIGN KEY (dst_kind, dst_ref_id) REFERENCES public.assets(kind, ref_id) ON DELETE CASCADE;



ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT fk_asset_rel_src FOREIGN KEY (src_kind, src_ref_id) REFERENCES public.assets(kind, ref_id) ON DELETE CASCADE;



ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT fk_output_compliance_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;



ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT fk_prompt_injection_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;



ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT fk_session_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;



ALTER TABLE ONLY public.prompt_injection_detections
    ADD CONSTRAINT prompt_injection_detections_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES public.prompt_injection_rules(id) ON DELETE SET NULL;



ALTER TABLE public.agent_relationships ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.analysis_events ENABLE ROW LEVEL SECURITY;


CREATE POLICY analysis_events_super_admin_bypass ON public.analysis_events USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));



ALTER TABLE public.approval_queue ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.armor_judgments ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.asset_relationships ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.billing_orders ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.credit_ledger_old ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.intent_aggregates ENABLE ROW LEVEL SECURITY;


CREATE POLICY intent_aggregates_super_admin_bypass ON public.intent_aggregates USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));



ALTER TABLE public.output_compliance_audit ENABLE ROW LEVEL SECURITY;


CREATE POLICY output_compliance_audit_super_admin ON public.output_compliance_audit USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));



CREATE POLICY output_compliance_audit_tenant ON public.output_compliance_audit USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



ALTER TABLE public.output_compliance_policies ENABLE ROW LEVEL SECURITY;


CREATE POLICY output_compliance_policies_super_admin ON public.output_compliance_policies USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));



CREATE POLICY output_compliance_policies_tenant ON public.output_compliance_policies USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



ALTER TABLE public.prompt_injection_detections ENABLE ROW LEVEL SECURITY;


CREATE POLICY prompt_injection_detections_super_admin ON public.prompt_injection_detections USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));



CREATE POLICY prompt_injection_detections_tenant ON public.prompt_injection_detections USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



ALTER TABLE public.prompt_injection_policies ENABLE ROW LEVEL SECURITY;


CREATE POLICY prompt_injection_policies_super_admin ON public.prompt_injection_policies USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));



CREATE POLICY prompt_injection_policies_tenant ON public.prompt_injection_policies USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



ALTER TABLE public.request_logs ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.request_logs_archive ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.response_format_anomalies ENABLE ROW LEVEL SECURITY;


CREATE POLICY response_format_anomalies_super_admin ON public.response_format_anomalies USING ((current_setting('app.bypass_rls'::text, true) = 'true'::text));



CREATE POLICY response_format_anomalies_tenant_isolation ON public.response_format_anomalies USING (((tenant_id IS NULL) OR (tenant_id = public.get_current_tenant())));



ALTER TABLE public.routing_decision_log_archive ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.session_audit_records ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.session_summaries ENABLE ROW LEVEL SECURITY;


CREATE POLICY session_summaries_super_admin_bypass ON public.session_summaries USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));



CREATE POLICY session_summaries_tenant_isolation ON public.session_summaries USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



ALTER TABLE public.settings_audit ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tenant_credit_wallets ENABLE ROW LEVEL SECURITY;


CREATE POLICY tenant_isolation_agent_relationships ON public.agent_relationships USING (((EXISTS ( SELECT 1
   FROM public.agents a_src
  WHERE ((a_src.id = agent_relationships.src_agent_id) AND (a_src.tenant_id = public.get_current_tenant())))) AND (EXISTS ( SELECT 1
   FROM public.agents a_dst
  WHERE ((a_dst.id = agent_relationships.dst_agent_id) AND (a_dst.tenant_id = public.get_current_tenant()))))));



CREATE POLICY tenant_isolation_agents ON public.agents USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_analysis_events ON public.analysis_events USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_approval_queue ON public.approval_queue USING (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text)))) WITH CHECK (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text))));



CREATE POLICY tenant_isolation_armor_judgments ON public.armor_judgments USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_asset_relationships ON public.asset_relationships USING (((EXISTS ( SELECT 1
   FROM public.assets a_src
  WHERE ((a_src.kind = asset_relationships.src_kind) AND (a_src.ref_id = asset_relationships.src_ref_id) AND (a_src.tenant_id = public.get_current_tenant())))) AND (EXISTS ( SELECT 1
   FROM public.assets a_dst
  WHERE ((a_dst.kind = asset_relationships.dst_kind) AND (a_dst.ref_id = asset_relationships.dst_ref_id) AND (a_dst.tenant_id = public.get_current_tenant()))))));



CREATE POLICY tenant_isolation_assets ON public.assets USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_attachments ON public.attachments USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_billing_orders ON public.billing_orders USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_credit_ledger ON public.credit_ledger_old USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_intent_aggregates ON public.intent_aggregates USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_request_logs ON public.request_logs USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_request_logs_archive ON public.request_logs_archive USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive USING ((tenant_id = public.get_current_tenant()));



CREATE POLICY tenant_isolation_session_audit_records ON public.session_audit_records USING (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text)))) WITH CHECK (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text))));



CREATE POLICY tenant_isolation_settings_audit ON public.settings_audit USING ((((tenant_id)::text = public.get_current_tenant()) OR (tenant_id IS NULL)));



CREATE POLICY tenant_isolation_tenant_credit_wallets ON public.tenant_credit_wallets USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_tenant_settings_kv ON public.tenant_settings_kv USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_tenant_subscriptions ON public.tenant_subscriptions USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_tenant_tool_policies ON public.tenant_tool_policies USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_tmp ON public.tenant_model_policies USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_tmp_audit ON public.tenant_model_policies_audit USING (((tenant_id = public.get_current_tenant()) OR (tenant_id IS NULL)));



CREATE POLICY tenant_isolation_tool_call_events ON public.tool_call_events USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_tool_registry ON public.tool_registry USING ((((tenant_id)::text = public.get_current_tenant()) OR (tenant_id IS NULL) OR ((tenant_id)::text = 'default'::text)));



CREATE POLICY tenant_isolation_tool_usage_stats ON public.tool_usage_stats USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_tool_usage_stats ON public.tool_usage_stats_old USING (((tenant_id)::text = public.get_current_tenant()));



CREATE POLICY tenant_isolation_users ON public.users USING (((tenant_id)::text = public.get_current_tenant()));



ALTER TABLE public.tenant_model_policies ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tenant_model_policies_audit ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tenant_settings_kv ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tenant_tool_policies ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tool_call_events ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tool_registry ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tool_usage_stats ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.tool_usage_stats_old ENABLE ROW LEVEL SECURITY;


ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;


\unrestrict gPTdVF5pygRVg5OtxjSw7R5LSQeQdkf3y9lWljr23YJHvrZ9yTcmxkU0xcVJIJT

