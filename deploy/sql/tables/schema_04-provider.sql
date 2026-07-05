-- ============================================
-- LLM Gateway Database Schema
-- Category: 04-provider
-- Generated: 2026-07-05 17:14:32
-- ============================================

-- ----------------------------------------
-- Table: provider_catalog
-- ----------------------------------------






-- Name: provider_catalog; Type: TABLE; Schema: public; Owner: -

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


-- Name: COLUMN provider_catalog.models_endpoint_template; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.provider_catalog.models_endpoint_template IS '模型清单 API 模板：NULL=自动推导；/models 或 /v1/models 追加到 base_url；https://… 全 URL；空串=仅 manifest';


-- Name: COLUMN provider_catalog.capabilities; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.provider_catalog.capabilities IS 'Per-catalog capability flags and request sanitization config';


-- Name: COLUMN provider_catalog.vendor_name; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.provider_catalog.vendor_name IS 'Human-readable vendor name for grouped view, e.g. "OpenAI", "Anthropic", "DeepSeek"';



\unrestrict tvXmlwRvaWkKJ9kxMu6aW8ecglw3qig9UobPOXcnVC0EcMzuUGf8QwtN5YZhFW0


-- ----------------------------------------
-- Table: provider_events
-- ----------------------------------------






-- Name: provider_events; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.provider_events (
    id bigint,
    credential_id bigint,
    event_kind text,
    payload_json jsonb,
    ts timestamp with time zone
);



\unrestrict H8T4157au6rc7i6RgXZCUWWnDpw6ELhTc5dxal3VEjMbvuU29DB24K66XndPsKN


-- ----------------------------------------
-- Table: provider_header_profiles
-- ----------------------------------------






-- Name: provider_header_profiles; Type: TABLE; Schema: public; Owner: -

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


-- Name: provider_header_profiles_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.provider_header_profiles_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: provider_header_profiles_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.provider_header_profiles_id_seq OWNED BY public.provider_header_profiles.id;


-- Name: provider_header_profiles id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_header_profiles ALTER COLUMN id SET DEFAULT nextval('public.provider_header_profiles_id_seq'::regclass);


-- Name: provider_header_profiles provider_header_profiles_profile_code_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_header_profiles
    ADD CONSTRAINT provider_header_profiles_profile_code_key UNIQUE (profile_code);



\unrestrict Dn6SlW0Y4gwTuYXHth3qLgV9T53ftX7bJ30OJmrIgz6ApsVKNiInaMfom8oKJoR


-- ----------------------------------------
-- Table: provider_models
-- ----------------------------------------






-- Name: provider_models; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE provider_models; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.provider_models IS 'Provider-exposed models: one row per (provider, raw_model_name)';


-- Name: COLUMN provider_models.canonical_id; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.provider_models.canonical_id IS 'FK to models_canonical.id for canonical name resolution';


-- Name: provider_models_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.provider_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: provider_models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.provider_models_id_seq OWNED BY public.provider_models.id;


-- Name: provider_models id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_models ALTER COLUMN id SET DEFAULT nextval('public.provider_models_id_seq'::regclass);


-- Name: provider_models provider_models_unique_provider_model; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_models
    ADD CONSTRAINT provider_models_unique_provider_model UNIQUE (provider_id, raw_model_name);


-- Name: idx_provider_models_canonical_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_provider_models_canonical_id ON public.provider_models USING btree (canonical_id);


-- Name: idx_provider_models_lower_raw_model_name; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_provider_models_lower_raw_model_name ON public.provider_models USING btree (lower(raw_model_name));


-- Name: idx_provider_models_lower_standardized_name; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_provider_models_lower_standardized_name ON public.provider_models USING btree (lower(standardized_name));



\unrestrict aMxgeEM3Ks2CPS18xX5L2gw6hORD69SZKfsJNon5Coy5HouUgRRVkJAQfaUk2oQ


-- ----------------------------------------
-- Table: provider_quality_rollup
-- ----------------------------------------






-- Name: provider_quality_rollup; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.provider_quality_rollup (
    provider_id integer NOT NULL,
    bucket_start timestamp with time zone NOT NULL,
    total_requests integer DEFAULT 0 NOT NULL,
    bad_requests integer DEFAULT 0 NOT NULL,
    fixed_requests integer DEFAULT 0 NOT NULL,
    avg_quality_score numeric(3,2),
    top_flag text
);


-- Name: provider_quality_rollup provider_quality_rollup_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_quality_rollup
    ADD CONSTRAINT provider_quality_rollup_pkey PRIMARY KEY (provider_id, bucket_start);


-- Name: idx_provider_quality_rollup_bucket; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_provider_quality_rollup_bucket ON public.provider_quality_rollup USING btree (bucket_start DESC);



\unrestrict iI9vTBeZY1BajwdxoShsbPKQYBBT8clw8YHzZM4GJhbjeDrFxl1GoAH3Ww0JkYf


-- ----------------------------------------
-- Table: provider_scores
-- ----------------------------------------






-- Name: provider_scores; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.provider_scores (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    canonical_id bigint,
    score numeric(6,4) NOT NULL,
    factors_json jsonb,
    computed_at timestamp with time zone DEFAULT now() NOT NULL
);


-- Name: provider_scores_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.provider_scores_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: provider_scores_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.provider_scores_id_seq OWNED BY public.provider_scores.id;


-- Name: provider_scores id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_scores ALTER COLUMN id SET DEFAULT nextval('public.provider_scores_id_seq'::regclass);



\unrestrict GU7HW6IKxkadG3yYn44OOZJwc8gQetQue7WndIpya1KA3mDPNNFreoDYFkDhehj


-- ----------------------------------------
-- Table: provider_settings
-- ----------------------------------------






-- Name: provider_settings; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE provider_settings; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.provider_settings IS 'Provider级别的配置覆盖，优先级高于平台默认配置';


-- Name: COLUMN provider_settings.setting_key; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.provider_settings.setting_key IS '配置键，如: compression.mode, cache.enabled, format_conversion.enabled';


-- Name: COLUMN provider_settings.setting_value; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.provider_settings.setting_value IS '配置值，JSON格式，如: "off", true, false';


-- Name: COLUMN provider_settings.enabled; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.provider_settings.enabled IS '是否启用该配置覆盖';


-- Name: provider_settings_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.provider_settings_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: provider_settings_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.provider_settings_id_seq OWNED BY public.provider_settings.id;


-- Name: provider_settings id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_settings ALTER COLUMN id SET DEFAULT nextval('public.provider_settings_id_seq'::regclass);


-- Name: provider_settings provider_settings_unique_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.provider_settings
    ADD CONSTRAINT provider_settings_unique_key UNIQUE (provider_id, setting_key);


-- Name: idx_provider_settings_key; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_provider_settings_key ON public.provider_settings USING btree (setting_key) WHERE (enabled = true);


-- Name: idx_provider_settings_provider; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_provider_settings_provider ON public.provider_settings USING btree (provider_id) WHERE (enabled = true);


-- Name: provider_settings trigger_provider_settings_updated_at; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trigger_provider_settings_updated_at BEFORE UPDATE ON public.provider_settings FOR EACH ROW EXECUTE FUNCTION public.update_provider_settings_updated_at();



\unrestrict MMbEg4mXpRn5V2gqHdzdKNlLu2807CMhiVMtZ0J3V6b40RE60dL1UBUhJdobxd6


-- ----------------------------------------
-- Table: providers
-- ----------------------------------------






-- Name: providers; Type: TABLE; Schema: public; Owner: -

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


-- Name: COLUMN providers.quality_fix_mode; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.providers.quality_fix_mode IS 'off         : passthrough, no detection, no rewrite.
     detect_only : detect tool_call quality issues, write request_log signals,
                   but do NOT modify the response body sent to the client.
     fix         : detect + write signals + rewrite the response body
                   (rename empty names, dedup ids, etc.) before forwarding.';


-- Name: providers_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.providers_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: providers_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.providers_id_seq OWNED BY public.providers.id;


-- Name: providers id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.providers ALTER COLUMN id SET DEFAULT nextval('public.providers_id_seq'::regclass);


-- Name: providers providers_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_pkey PRIMARY KEY (id);


-- Name: providers providers_tenant_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.providers
    ADD CONSTRAINT providers_tenant_id_code_key UNIQUE (tenant_id, code);


-- Name: providers trg_notify_auto_route_providers; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_notify_auto_route_providers AFTER UPDATE OF enabled, manual_disabled ON public.providers FOR EACH ROW WHEN ((old.* IS DISTINCT FROM new.*)) EXECUTE FUNCTION public.notify_auto_route_refresh();



\unrestrict I9NwLI0AdxQ7arpfVWO7VlrmwzwPwBJByvaVmBw9jHxmemDrQoHc4QK91ILsQSH


