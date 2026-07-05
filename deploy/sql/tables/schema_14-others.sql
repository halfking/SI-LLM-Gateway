-- ============================================
-- LLM Gateway Database Schema
-- Category: 14-others
-- Generated: 2026-07-05 17:14:23
-- ============================================

-- ----------------------------------------
-- Table: agent_relationships
-- ----------------------------------------






-- Name: agent_relationships; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.agent_relationships (
    src_agent_id bigint NOT NULL,
    dst_agent_id bigint NOT NULL,
    rel text NOT NULL,
    weight double precision DEFAULT 1.0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT chk_agent_rel CHECK ((rel = ANY (ARRAY['calls'::text, 'delegates'::text, 'depends_on'::text, 'similar_to'::text]))),
    CONSTRAINT chk_agent_rel_no_self CHECK ((src_agent_id <> dst_agent_id))
);


-- Name: agent_relationships pk_agent_relationships; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT pk_agent_relationships PRIMARY KEY (src_agent_id, dst_agent_id, rel);


-- Name: idx_agent_rel_dst; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_agent_rel_dst ON public.agent_relationships USING btree (dst_agent_id);


-- Name: idx_agent_rel_src; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_agent_rel_src ON public.agent_relationships USING btree (src_agent_id);


-- Name: agent_relationships fk_agent_rel_dst; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT fk_agent_rel_dst FOREIGN KEY (dst_agent_id) REFERENCES public.agents(id) ON DELETE CASCADE;


-- Name: agent_relationships fk_agent_rel_src; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.agent_relationships
    ADD CONSTRAINT fk_agent_rel_src FOREIGN KEY (src_agent_id) REFERENCES public.agents(id) ON DELETE CASCADE;


-- Name: agent_relationships; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.agent_relationships ENABLE ROW LEVEL SECURITY;

-- Name: agent_relationships tenant_isolation_agent_relationships; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_agent_relationships ON public.agent_relationships USING (((EXISTS ( SELECT 1
   FROM public.agents a_src
  WHERE ((a_src.id = agent_relationships.src_agent_id) AND (a_src.tenant_id = public.get_current_tenant())))) AND (EXISTS ( SELECT 1
   FROM public.agents a_dst
  WHERE ((a_dst.id = agent_relationships.dst_agent_id) AND (a_dst.tenant_id = public.get_current_tenant()))))));



\unrestrict 8jHECAhgP2TAspkwJ8OzgllPqJUdUkeTUgHjBTKHqJERH9Y4NLEsMO8UBTds5tn


-- ----------------------------------------
-- Table: analysis_events
-- ----------------------------------------






-- Name: analysis_events; Type: TABLE; Schema: public; Owner: -

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


-- Name: analysis_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.analysis_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: analysis_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.analysis_events_id_seq OWNED BY public.analysis_events.id;


-- Name: analysis_events id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.analysis_events ALTER COLUMN id SET DEFAULT nextval('public.analysis_events_id_seq'::regclass);


-- Name: analysis_events analysis_events_event_id_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.analysis_events
    ADD CONSTRAINT analysis_events_event_id_key UNIQUE (event_id);


-- Name: analysis_events analysis_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.analysis_events
    ADD CONSTRAINT analysis_events_pkey PRIMARY KEY (id);


-- Name: idx_analysis_events_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_analysis_events_session ON public.analysis_events USING btree (session_id, occurred_at DESC) WHERE (session_id IS NOT NULL);


-- Name: idx_analysis_events_tenant_type; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_analysis_events_tenant_type ON public.analysis_events USING btree (tenant_id, type, occurred_at DESC);


-- Name: idx_analysis_events_unprocessed; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_analysis_events_unprocessed ON public.analysis_events USING btree (occurred_at) WHERE (processed_at IS NULL);


-- Name: analysis_events; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.analysis_events ENABLE ROW LEVEL SECURITY;

-- Name: analysis_events analysis_events_super_admin_bypass; Type: POLICY; Schema: public; Owner: -

CREATE POLICY analysis_events_super_admin_bypass ON public.analysis_events USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


-- Name: analysis_events tenant_isolation_analysis_events; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_analysis_events ON public.analysis_events USING ((tenant_id = public.get_current_tenant()));



\unrestrict qOevaZRcTs2gV8exg3Etz6wooYfO6REg2J9M8g8kWfVxuNc2OmB0ahdCgiyjvN5


-- ----------------------------------------
-- Table: approval_queue
-- ----------------------------------------






-- Name: approval_queue; Type: TABLE; Schema: public; Owner: -

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


-- Name: approval_queue approval_queue_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.approval_queue
    ADD CONSTRAINT approval_queue_pkey PRIMARY KEY (id);


-- Name: idx_approval_queue_expires; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_approval_queue_expires ON public.approval_queue USING btree (expires_at) WHERE (status = 'pending'::text);


-- Name: idx_approval_queue_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_approval_queue_session ON public.approval_queue USING btree (session_id, created_at DESC);


-- Name: idx_approval_queue_tenant_pending; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_approval_queue_tenant_pending ON public.approval_queue USING btree (tenant_id, created_at DESC) WHERE (status = 'pending'::text);


-- Name: approval_queue; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.approval_queue ENABLE ROW LEVEL SECURITY;

-- Name: approval_queue tenant_isolation_approval_queue; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_approval_queue ON public.approval_queue USING (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text)))) WITH CHECK (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text))));



\unrestrict NcKoXR6SO2OFUUu46AzpEdvy2T9h1OI5i1qOKHQQZAtJfaHR077xl8rLCliYQSu


-- ----------------------------------------
-- Table: armor_judgments
-- ----------------------------------------






-- Name: armor_judgments; Type: TABLE; Schema: public; Owner: -

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


-- Name: armor_judgments_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.armor_judgments_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: armor_judgments_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.armor_judgments_id_seq OWNED BY public.armor_judgments.id;


-- Name: armor_judgments id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.armor_judgments ALTER COLUMN id SET DEFAULT nextval('public.armor_judgments_id_seq'::regclass);


-- Name: armor_judgments armor_judgments_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.armor_judgments
    ADD CONSTRAINT armor_judgments_pkey PRIMARY KEY (id);


-- Name: idx_armor_judgments_request; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_armor_judgments_request ON public.armor_judgments USING btree (request_id);


-- Name: idx_armor_judgments_stats; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_armor_judgments_stats ON public.armor_judgments USING btree (check_type, decision);


-- Name: idx_armor_judgments_tenant_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_armor_judgments_tenant_time ON public.armor_judgments USING btree (tenant_id, created_at DESC);


-- Name: armor_judgments; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.armor_judgments ENABLE ROW LEVEL SECURITY;

-- Name: armor_judgments tenant_isolation_armor_judgments; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_armor_judgments ON public.armor_judgments USING ((tenant_id = public.get_current_tenant()));



\unrestrict m66kVHeyeWgb9YsfWmu5wPIoZhTPhjXEgcCHHGYC8tTxDYA9DBPQRuwOcvN6vbd


-- ----------------------------------------
-- Table: asset_relationships
-- ----------------------------------------






-- Name: asset_relationships; Type: TABLE; Schema: public; Owner: -

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


-- Name: asset_relationships pk_asset_relationships; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT pk_asset_relationships PRIMARY KEY (src_kind, src_ref_id, dst_kind, dst_ref_id, rel);


-- Name: idx_asset_rel_dst; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_asset_rel_dst ON public.asset_relationships USING btree (dst_kind, dst_ref_id);


-- Name: idx_asset_rel_src; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_asset_rel_src ON public.asset_relationships USING btree (src_kind, src_ref_id);


-- Name: asset_relationships fk_asset_rel_dst; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT fk_asset_rel_dst FOREIGN KEY (dst_kind, dst_ref_id) REFERENCES public.assets(kind, ref_id) ON DELETE CASCADE;


-- Name: asset_relationships fk_asset_rel_src; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT fk_asset_rel_src FOREIGN KEY (src_kind, src_ref_id) REFERENCES public.assets(kind, ref_id) ON DELETE CASCADE;


-- Name: asset_relationships; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.asset_relationships ENABLE ROW LEVEL SECURITY;

-- Name: asset_relationships tenant_isolation_asset_relationships; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_asset_relationships ON public.asset_relationships USING (((EXISTS ( SELECT 1
   FROM public.assets a_src
  WHERE ((a_src.kind = asset_relationships.src_kind) AND (a_src.ref_id = asset_relationships.src_ref_id) AND (a_src.tenant_id = public.get_current_tenant())))) AND (EXISTS ( SELECT 1
   FROM public.assets a_dst
  WHERE ((a_dst.kind = asset_relationships.dst_kind) AND (a_dst.ref_id = asset_relationships.dst_ref_id) AND (a_dst.tenant_id = public.get_current_tenant()))))));



\unrestrict yfzN6tblW5HVFVpdIz80KRHSXdoWWBBoFKKy1uEP4Njr7UL1m2Ig5PfP48oc060


-- ----------------------------------------
-- Table: assets
-- ----------------------------------------






-- Name: assets; Type: TABLE; Schema: public; Owner: -

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


-- Name: assets pk_assets; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.assets
    ADD CONSTRAINT pk_assets PRIMARY KEY (kind, ref_id);


-- Name: idx_assets_tags; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_assets_tags ON public.assets USING gin (tags jsonb_path_ops);


-- Name: idx_assets_tenant_kind; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_assets_tenant_kind ON public.assets USING btree (tenant_id, kind);


-- Name: assets; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;

-- Name: assets tenant_isolation_assets; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_assets ON public.assets USING ((tenant_id = public.get_current_tenant()));



\unrestrict ECtBogF3hulgLV0UMgm9uc8dhQqVTSO1dQFdodL9nfMERLei3U0g8dAgy2t9E5i


-- ----------------------------------------
-- Table: billing_orders
-- ----------------------------------------






-- Name: billing_orders; Type: TABLE; Schema: public; Owner: -

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


-- Name: billing_orders_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.billing_orders_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: billing_orders_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.billing_orders_id_seq OWNED BY public.billing_orders.id;


-- Name: billing_orders id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.billing_orders ALTER COLUMN id SET DEFAULT nextval('public.billing_orders_id_seq'::regclass);


-- Name: billing_orders billing_orders_order_no_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.billing_orders
    ADD CONSTRAINT billing_orders_order_no_key UNIQUE (order_no);


-- Name: idx_billing_orders_status; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_billing_orders_status ON public.billing_orders USING btree (status, created_at DESC);


-- Name: idx_billing_orders_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_billing_orders_tenant ON public.billing_orders USING btree (tenant_id, created_at DESC);


-- Name: billing_orders; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.billing_orders ENABLE ROW LEVEL SECURITY;

-- Name: billing_orders tenant_isolation_billing_orders; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_billing_orders ON public.billing_orders USING (((tenant_id)::text = public.get_current_tenant()));



\unrestrict dqk5DUivdAjhauk6JPKJyes0TOSjGPEQTcJFUSA3cslWgpPK0DWAGCKP8UJvRG0


-- ----------------------------------------
-- Table: goal_sessions
-- ----------------------------------------






-- Name: goal_sessions; Type: TABLE; Schema: public; Owner: -

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


-- Name: goal_sessions_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.goal_sessions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: goal_sessions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.goal_sessions_id_seq OWNED BY public.goal_sessions.id;


-- Name: goal_sessions id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.goal_sessions ALTER COLUMN id SET DEFAULT nextval('public.goal_sessions_id_seq'::regclass);


-- Name: goal_sessions goal_sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.goal_sessions
    ADD CONSTRAINT goal_sessions_pkey PRIMARY KEY (id);


-- Name: goal_sessions goal_sessions_session_id_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.goal_sessions
    ADD CONSTRAINT goal_sessions_session_id_key UNIQUE (session_id);


-- Name: idx_goal_sessions_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_goal_sessions_session ON public.goal_sessions USING btree (session_id);


-- Name: idx_goal_sessions_state; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_goal_sessions_state ON public.goal_sessions USING btree (state, last_activity_at);


-- Name: idx_goal_sessions_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_goal_sessions_tenant ON public.goal_sessions USING btree (tenant_id, state);



\unrestrict mqrIh906Jj8iA4HLWZfhvO2KqlI2iEKaXWvmDez90XpxcR2gldT13rdqRT84dr6


-- ----------------------------------------
-- Table: intent_aggregates
-- ----------------------------------------






-- Name: intent_aggregates; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.intent_aggregates (
    tenant_id text NOT NULL,
    intent_kind text NOT NULL,
    count bigint DEFAULT 0 NOT NULL,
    last_updated timestamp with time zone DEFAULT now() NOT NULL
);


-- Name: intent_aggregates intent_aggregates_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.intent_aggregates
    ADD CONSTRAINT intent_aggregates_pkey PRIMARY KEY (tenant_id, intent_kind);


-- Name: idx_intent_aggregates_tenant_updated; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_intent_aggregates_tenant_updated ON public.intent_aggregates USING btree (tenant_id, last_updated DESC);


-- Name: intent_aggregates; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.intent_aggregates ENABLE ROW LEVEL SECURITY;

-- Name: intent_aggregates intent_aggregates_super_admin_bypass; Type: POLICY; Schema: public; Owner: -

CREATE POLICY intent_aggregates_super_admin_bypass ON public.intent_aggregates USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


-- Name: intent_aggregates tenant_isolation_intent_aggregates; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_intent_aggregates ON public.intent_aggregates USING ((tenant_id = public.get_current_tenant()));



\unrestrict kGuviKeYzJpvfM1G8z95cZoQQqqq6WxfM58Qbj1HsVWUVaqZ4EqEaP9fLaFmK1g


-- ----------------------------------------
-- Table: internal_service_keys
-- ----------------------------------------






-- Name: internal_service_keys; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE internal_service_keys; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.internal_service_keys IS 'Registry of HMAC secrets for internal service-to-service authentication.
     The actual secret is stored in INTERNAL_SERVICE_KEYS_JSON env var (not here).
     This table tracks registration metadata and last-used timestamps for audit.';



\unrestrict t5uqtlR0gMo1mz6i5JV1pT7tYCQGOevgWKPyMBxyHkfNQgYOiDf40tEhYDtmpey


-- ----------------------------------------
-- Table: key_applications
-- ----------------------------------------






-- Name: key_applications; Type: TABLE; Schema: public; Owner: -

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


-- Name: key_applications trg_key_applications_updated_at; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_key_applications_updated_at BEFORE UPDATE ON public.key_applications FOR EACH ROW EXECUTE FUNCTION public.key_applications_set_updated_at();



\unrestrict z54AmBrD4jJtccU7oJvux4CoKbsf4Fpu43TzKLVoxlQbwmDHWSStUGyy9MhvxqB


-- ----------------------------------------
-- Table: key_rpm_daily
-- ----------------------------------------






-- Name: key_rpm_daily; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.key_rpm_daily (
    api_key_id bigint NOT NULL,
    day_bucket date NOT NULL,
    peak_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    avg_rpm numeric(10,3) DEFAULT 0 NOT NULL,
    request_count bigint DEFAULT 0 NOT NULL
);



\unrestrict vz0pkg71gsDYhEO8hLv8zebfoxukKMQueyN3DVpDnxtuaSAhy2xsd8NZb7tS782


-- ----------------------------------------
-- Table: local_models
-- ----------------------------------------






-- Name: local_models; Type: TABLE; Schema: public; Owner: -

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


-- Name: local_models_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.local_models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: local_models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.local_models_id_seq OWNED BY public.local_models.id;


-- Name: local_models id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.local_models ALTER COLUMN id SET DEFAULT nextval('public.local_models_id_seq'::regclass);


-- Name: local_models local_models_runtime_id_raw_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.local_models
    ADD CONSTRAINT local_models_runtime_id_raw_name_key UNIQUE (runtime_id, raw_name);



\unrestrict j6ZVi0EuAK16PwZnQaGSLsua8MOuq83bEH436WbScWfarKCvVKZVTgEwleLPqEu


-- ----------------------------------------
-- Table: local_runtimes
-- ----------------------------------------






-- Name: local_runtimes; Type: TABLE; Schema: public; Owner: -

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


-- Name: local_runtimes_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.local_runtimes_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: local_runtimes_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.local_runtimes_id_seq OWNED BY public.local_runtimes.id;


-- Name: local_runtimes id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.local_runtimes ALTER COLUMN id SET DEFAULT nextval('public.local_runtimes_id_seq'::regclass);


-- Name: local_runtimes local_runtimes_host_code_runtime_type_base_url_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.local_runtimes
    ADD CONSTRAINT local_runtimes_host_code_runtime_type_base_url_key UNIQUE (host_code, runtime_type, base_url);



\unrestrict XQndyFxr7YZobtUvK2K6nn8hd28YLo6JuhMdml7Y11I8uH5fpzaGLOnQdUlBkpC


-- ----------------------------------------
-- Table: maas_settings
-- ----------------------------------------






-- Name: maas_settings; Type: TABLE; Schema: public; Owner: -

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


-- Name: maas_settings maas_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.maas_settings
    ADD CONSTRAINT maas_settings_pkey PRIMARY KEY (id);



\unrestrict ktya2e9839wdjv7817PvMsfXU37AsgRBVmj7GBG37hVc4UDCBxu8Ia0HXdg1aGr


-- ----------------------------------------
-- Table: ops_model_offers_backup
-- ----------------------------------------






-- Name: ops_model_offers_backup; Type: TABLE; Schema: public; Owner: -

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


-- Name: ops_model_offers_backup_backup_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.ops_model_offers_backup_backup_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: ops_model_offers_backup_backup_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.ops_model_offers_backup_backup_id_seq OWNED BY public.ops_model_offers_backup.backup_id;


-- Name: ops_model_offers_backup backup_id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.ops_model_offers_backup ALTER COLUMN backup_id SET DEFAULT nextval('public.ops_model_offers_backup_backup_id_seq'::regclass);



\unrestrict hQqKD9vGiTi4D7iInyhBCBVrol7AfgK3c1WxAr1DcwcNw4Cl7BejT5TtQgfL5Oq


-- ----------------------------------------
-- Table: output_compliance_policies
-- ----------------------------------------






-- Name: output_compliance_policies; Type: TABLE; Schema: public; Owner: -

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


-- Name: output_compliance_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.output_compliance_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: output_compliance_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.output_compliance_policies_id_seq OWNED BY public.output_compliance_policies.id;


-- Name: output_compliance_policies id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.output_compliance_policies ALTER COLUMN id SET DEFAULT nextval('public.output_compliance_policies_id_seq'::regclass);


-- Name: output_compliance_policies output_compliance_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT output_compliance_policies_pkey PRIMARY KEY (id);


-- Name: output_compliance_policies unique_output_compliance_tenant; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT unique_output_compliance_tenant UNIQUE (tenant_id);


-- Name: output_compliance_policies fk_output_compliance_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.output_compliance_policies
    ADD CONSTRAINT fk_output_compliance_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;


-- Name: output_compliance_policies; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.output_compliance_policies ENABLE ROW LEVEL SECURITY;

-- Name: output_compliance_policies output_compliance_policies_super_admin; Type: POLICY; Schema: public; Owner: -

CREATE POLICY output_compliance_policies_super_admin ON public.output_compliance_policies USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


-- Name: output_compliance_policies output_compliance_policies_tenant; Type: POLICY; Schema: public; Owner: -

CREATE POLICY output_compliance_policies_tenant ON public.output_compliance_policies USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



\unrestrict pVeOfQeNkJbz12XDFaeQoZdfEWKQ7SoBpoy44ZwNggZbeARd9PylfEYs7LsDxii


-- ----------------------------------------
-- Table: passive_probe_state
-- ----------------------------------------






-- Name: passive_probe_state; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE passive_probe_state; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.passive_probe_state IS 'v5: Passive observation state for Layer 5. Accumulates consecutive errors from request_logs for the secondary-verification trigger (consecutive>=3 or error_rate>=0.6).';


-- Name: passive_probe_state passive_probe_state_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.passive_probe_state
    ADD CONSTRAINT passive_probe_state_pkey PRIMARY KEY (credential_id, raw_model_name, error_kind);


-- Name: idx_passive_probe_reviewing; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_passive_probe_reviewing ON public.passive_probe_state USING btree (in_reviewing, reviewing_until) WHERE (in_reviewing = true);



\unrestrict G3kwytvPDWOzbmWDBAyR4TWrzEGeWzxUl8MhJKmidARp6mnpOh9pU4XVg22A3dC


-- ----------------------------------------
-- Table: pii_patterns
-- ----------------------------------------






-- Name: pii_patterns; Type: TABLE; Schema: public; Owner: -

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


-- Name: pii_patterns_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.pii_patterns_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: pii_patterns_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.pii_patterns_id_seq OWNED BY public.pii_patterns.id;


-- Name: pii_patterns id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.pii_patterns ALTER COLUMN id SET DEFAULT nextval('public.pii_patterns_id_seq'::regclass);


-- Name: pii_patterns pii_patterns_pattern_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.pii_patterns
    ADD CONSTRAINT pii_patterns_pattern_name_key UNIQUE (pattern_name);


-- Name: pii_patterns pii_patterns_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.pii_patterns
    ADD CONSTRAINT pii_patterns_pkey PRIMARY KEY (id);



\unrestrict c0qapp9Lfj9qtQRCzORigh7QMPGUECsb3f0lCMVHjgFkWudTzXa8Unq59IdhKgu


-- ----------------------------------------
-- Table: price_change_events
-- ----------------------------------------






-- Name: price_change_events; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.price_change_events (
    id bigint,
    old_plan_id bigint,
    new_plan_id bigint,
    delta_json jsonb,
    detected_at timestamp with time zone,
    notify_channel text,
    applied boolean
);



\unrestrict nTG7topEBfTE1sDgjAGs7Uw7vbs9u2EPKAEslXDz9d9AUA1AvZzetQ0Zg9AhUqq


-- ----------------------------------------
-- Table: pricing_plans
-- ----------------------------------------






-- Name: pricing_plans; Type: TABLE; Schema: public; Owner: -

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


-- Name: COLUMN pricing_plans.plan_type; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.pricing_plans.plan_type IS 'Plan type: token (PAYG per-1M) | token_plan (prepaid credits/package, NEW 2026-06-12) | code_plan (subscription) | agent_plan (agent bundle) | seat (per seat) | request (per request) | compute_time | flat_quota | free';


-- Name: pricing_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.pricing_plans_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: pricing_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.pricing_plans_id_seq OWNED BY public.pricing_plans.id;


-- Name: pricing_plans id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.pricing_plans ALTER COLUMN id SET DEFAULT nextval('public.pricing_plans_id_seq'::regclass);



\unrestrict ZJ0bSaUuLffMpYDUmhLOaOzLYwKf2dX46T6NQaPW10kWswybYZByQ9EYxfEqf1P


-- ----------------------------------------
-- Table: prompt_injection_detections
-- ----------------------------------------






-- Name: prompt_injection_detections; Type: TABLE; Schema: public; Owner: -

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


-- Name: prompt_injection_detections_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.prompt_injection_detections_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: prompt_injection_detections_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.prompt_injection_detections_id_seq OWNED BY public.prompt_injection_detections.id;


-- Name: prompt_injection_detections id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_detections ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_detections_id_seq'::regclass);


-- Name: prompt_injection_detections prompt_injection_detections_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_detections
    ADD CONSTRAINT prompt_injection_detections_pkey PRIMARY KEY (id);


-- Name: idx_detections_request; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_detections_request ON public.prompt_injection_detections USING btree (request_id);


-- Name: idx_detections_risk; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_detections_risk ON public.prompt_injection_detections USING btree (tenant_id, risk_level) WHERE (blocked = true);


-- Name: idx_detections_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_detections_session ON public.prompt_injection_detections USING btree (session_key);


-- Name: idx_detections_tenant_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_detections_tenant_time ON public.prompt_injection_detections USING btree (tenant_id, detected_at DESC);


-- Name: prompt_injection_detections prompt_injection_detections_rule_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_detections
    ADD CONSTRAINT prompt_injection_detections_rule_id_fkey FOREIGN KEY (rule_id) REFERENCES public.prompt_injection_rules(id) ON DELETE SET NULL;


-- Name: prompt_injection_detections; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.prompt_injection_detections ENABLE ROW LEVEL SECURITY;

-- Name: prompt_injection_detections prompt_injection_detections_super_admin; Type: POLICY; Schema: public; Owner: -

CREATE POLICY prompt_injection_detections_super_admin ON public.prompt_injection_detections USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


-- Name: prompt_injection_detections prompt_injection_detections_tenant; Type: POLICY; Schema: public; Owner: -

CREATE POLICY prompt_injection_detections_tenant ON public.prompt_injection_detections USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



\unrestrict AWQDbNjCwfFUPrWvFjhYQbzYYFALXXQn2PIbd2fJhTFDfyYC9dtkePNROeQLghP


-- ----------------------------------------
-- Table: prompt_injection_policies
-- ----------------------------------------






-- Name: prompt_injection_policies; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.prompt_injection_policies (
    id integer NOT NULL,
    tenant_id character varying(255) NOT NULL,
    enabled boolean DEFAULT true,
    detection_mode character varying(20) DEFAULT 'observe'::character varying,
    enable_basic_rules boolean DEFAULT true,
    enable_advanced_rules boolean DEFAULT true,
    enable_heuristics boolean DEFAULT true,
    enable_ml_model boolean DEFAULT false,
    score_threshold_log integer DEFAULT 3,
    score_threshold_warn integer DEFAULT 6,
    score_threshold_sanitize integer DEFAULT 8,
    score_threshold_block integer DEFAULT 10,
    action_on_low_risk character varying(20) DEFAULT 'log'::character varying,
    action_on_medium_risk character varying(20) DEFAULT 'warn'::character varying,
    action_on_high_risk character varying(20) DEFAULT 'block'::character varying,
    whitelist_patterns text[],
    whitelist_users text[],
    notify_on_detection boolean DEFAULT false,
    notification_webhook character varying(500),
    notification_email character varying(255),
    total_detections integer DEFAULT 0,
    total_blocks integer DEFAULT 0,
    last_detection_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(255),
    updated_by character varying(255)
);


-- Name: prompt_injection_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.prompt_injection_policies_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: prompt_injection_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.prompt_injection_policies_id_seq OWNED BY public.prompt_injection_policies.id;


-- Name: prompt_injection_policies id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_policies ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_policies_id_seq'::regclass);


-- Name: prompt_injection_policies prompt_injection_policies_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT prompt_injection_policies_pkey PRIMARY KEY (id);


-- Name: prompt_injection_policies unique_tenant_policy; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT unique_tenant_policy UNIQUE (tenant_id);


-- Name: prompt_injection_policies fk_prompt_injection_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_policies
    ADD CONSTRAINT fk_prompt_injection_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;


-- Name: prompt_injection_policies; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.prompt_injection_policies ENABLE ROW LEVEL SECURITY;

-- Name: prompt_injection_policies prompt_injection_policies_super_admin; Type: POLICY; Schema: public; Owner: -

CREATE POLICY prompt_injection_policies_super_admin ON public.prompt_injection_policies USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


-- Name: prompt_injection_policies prompt_injection_policies_tenant; Type: POLICY; Schema: public; Owner: -

CREATE POLICY prompt_injection_policies_tenant ON public.prompt_injection_policies USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



\unrestrict AiUeohQIOWgKogRgTHv1s2cTFxvdFQhXbo6V2Tft1oQPdl1acbC7BQgBMnygxDM


-- ----------------------------------------
-- Table: prompt_injection_rules
-- ----------------------------------------






-- Name: prompt_injection_rules; Type: TABLE; Schema: public; Owner: -

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


-- Name: prompt_injection_rules_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.prompt_injection_rules_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: prompt_injection_rules_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.prompt_injection_rules_id_seq OWNED BY public.prompt_injection_rules.id;


-- Name: prompt_injection_rules id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_rules ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_rules_id_seq'::regclass);


-- Name: prompt_injection_rules prompt_injection_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_rules
    ADD CONSTRAINT prompt_injection_rules_pkey PRIMARY KEY (id);


-- Name: prompt_injection_rules prompt_injection_rules_rule_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.prompt_injection_rules
    ADD CONSTRAINT prompt_injection_rules_rule_name_key UNIQUE (rule_name);



\unrestrict Fta6ocC2fc62uEV9nhrPkaM8hxk0MDuiXzSooaXPikKRd3iAHTwg9fnNIusspda


-- ----------------------------------------
-- Table: response_format_anomalies
-- ----------------------------------------






-- Name: response_format_anomalies; Type: TABLE; Schema: public; Owner: -

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


-- Name: response_format_anomalies_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.response_format_anomalies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: response_format_anomalies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.response_format_anomalies_id_seq OWNED BY public.response_format_anomalies.id;


-- Name: response_format_anomalies id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.response_format_anomalies ALTER COLUMN id SET DEFAULT nextval('public.response_format_anomalies_id_seq'::regclass);


-- Name: response_format_anomalies response_format_anomalies_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.response_format_anomalies
    ADD CONSTRAINT response_format_anomalies_pkey PRIMARY KEY (id);


-- Name: idx_response_format_anomalies_detected_at; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_response_format_anomalies_detected_at ON public.response_format_anomalies USING btree (detected_at DESC);


-- Name: idx_response_format_anomalies_provider; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_response_format_anomalies_provider ON public.response_format_anomalies USING btree (provider_code, client_model) WHERE (provider_code IS NOT NULL);


-- Name: idx_response_format_anomalies_request_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_response_format_anomalies_request_id ON public.response_format_anomalies USING btree (request_id);


-- Name: idx_response_format_anomalies_type; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_response_format_anomalies_type ON public.response_format_anomalies USING btree (anomaly_type, detected_at DESC);


-- Name: idx_response_format_anomalies_unresolved; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_response_format_anomalies_unresolved ON public.response_format_anomalies USING btree (detected_at DESC) WHERE (NOT resolved);


-- Name: response_format_anomalies; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.response_format_anomalies ENABLE ROW LEVEL SECURITY;

-- Name: response_format_anomalies response_format_anomalies_super_admin; Type: POLICY; Schema: public; Owner: -

CREATE POLICY response_format_anomalies_super_admin ON public.response_format_anomalies USING ((current_setting('app.bypass_rls'::text, true) = 'true'::text));


-- Name: response_format_anomalies response_format_anomalies_tenant_isolation; Type: POLICY; Schema: public; Owner: -

CREATE POLICY response_format_anomalies_tenant_isolation ON public.response_format_anomalies USING (((tenant_id IS NULL) OR (tenant_id = public.get_current_tenant())));



\unrestrict d2JXgkJ0N45UPIYJeM0xKYTYkh1uEElaU5h965IAAkXaYhKOSntjWP27DLJVAwo


-- ----------------------------------------
-- Table: route_decisions
-- ----------------------------------------






-- Name: route_decisions; Type: TABLE; Schema: public; Owner: -

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


-- Name: route_decisions_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.route_decisions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: route_decisions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.route_decisions_id_seq OWNED BY public.route_decisions.id;


-- Name: route_decisions id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.route_decisions ALTER COLUMN id SET DEFAULT nextval('public.route_decisions_id_seq'::regclass);



\unrestrict yMDk4tgctN2Ee1Z1inxjBUg6JDKP2U100J1uQcL3fRx6igZv70KQWhKGCi2qUsu


-- ----------------------------------------
-- Table: settings_kv
-- ----------------------------------------






-- Name: settings_kv; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE settings_kv; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.settings_kv IS '平台级运行时设置（Q2: 立即生效）';


-- Name: COLUMN settings_kv.prev_value; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.settings_kv.prev_value IS '上次的值，用于一键回滚';


-- Name: idx_settings_kv_category; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_settings_kv_category ON public.settings_kv USING btree (category);


-- Name: idx_settings_kv_scope; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_settings_kv_scope ON public.settings_kv USING btree (scope);


-- Name: idx_settings_kv_updated; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_settings_kv_updated ON public.settings_kv USING btree (updated_at DESC);



\unrestrict 7ky1mSrJfQNSBj260ng7tSNILpbcsqrVsrMKnSS8194gzcXIoYLTtUjs1EczMGw


-- ----------------------------------------
-- Table: sticky_sessions
-- ----------------------------------------






-- Name: sticky_sessions; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.sticky_sessions (
    sticky_key text NOT NULL,
    credential_id bigint NOT NULL,
    set_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    canonical_id bigint,
    last_request_id text
);


-- Name: idx_sticky_sessions_sticky_key_unique; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX idx_sticky_sessions_sticky_key_unique ON public.sticky_sessions USING btree (sticky_key);



\unrestrict WfSNnh9rFxzwIrErsbSRZc7POgKcrZ74zpPr8VGVcngkElUjP354SBLgt86nSlq


-- ----------------------------------------
-- Table: subscription_plans
-- ----------------------------------------






-- Name: subscription_plans; Type: TABLE; Schema: public; Owner: -

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


-- Name: subscription_plans_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.subscription_plans_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: subscription_plans_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.subscription_plans_id_seq OWNED BY public.subscription_plans.id;


-- Name: subscription_plans id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.subscription_plans ALTER COLUMN id SET DEFAULT nextval('public.subscription_plans_id_seq'::regclass);


-- Name: subscription_plans subscription_plans_code_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.subscription_plans
    ADD CONSTRAINT subscription_plans_code_key UNIQUE (code);



\unrestrict iwYzftQxp8FZWTbn8g4Qbr8z4Qk1eaI6VDH7qTVYNgWdgfSomNIutKBobFyqmUd


-- ----------------------------------------
-- Table: system_identity_pool
-- ----------------------------------------






-- Name: system_identity_pool; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.system_identity_pool (
    id integer DEFAULT 1 NOT NULL,
    max_identities integer DEFAULT 10000 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    CONSTRAINT system_identity_pool_id_check CHECK ((id = 1))
);


-- Name: TABLE system_identity_pool; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.system_identity_pool IS 'Global cap on total distinct end-user identities the gateway will accept. Once this many unique fingerprints are active, new connections must reuse an existing fingerprint (round-robin among least-recently-used).';


-- Name: system_identity_pool system_identity_pool_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.system_identity_pool
    ADD CONSTRAINT system_identity_pool_pkey PRIMARY KEY (id);



\unrestrict CJP47U5pXPXTcLWBDeZzOvIWLtzgk3FKjkWoVgerKjbzugW5B0kcG16HmPJvg1t


-- ----------------------------------------
-- Table: test_columnar_new
-- ----------------------------------------






-- Name: test_columnar_new; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.test_columnar_new (
    id integer NOT NULL,
    tenant_id text,
    model text,
    prompt_tokens integer,
    completion_tokens integer,
    created_at timestamp with time zone DEFAULT now()
);



\unrestrict ufmaSXASau290AI7kKWc5vYO641K2RgpubupLRDxSLvDP4ZRo2upWXK5efXq6Rc


-- ----------------------------------------
-- Table: topup_packages
-- ----------------------------------------






-- Name: topup_packages; Type: TABLE; Schema: public; Owner: -

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


-- Name: topup_packages_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.topup_packages_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: topup_packages_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.topup_packages_id_seq OWNED BY public.topup_packages.id;


-- Name: topup_packages id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.topup_packages ALTER COLUMN id SET DEFAULT nextval('public.topup_packages_id_seq'::regclass);


-- Name: topup_packages topup_packages_code_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.topup_packages
    ADD CONSTRAINT topup_packages_code_key UNIQUE (code);



\unrestrict xRqPsGpKJylnV2dUi1HpGUkEaoQpHzw7fI6W3MeirqyZXgPaEeM81yRI6d8wESi


-- ----------------------------------------
-- Table: toxic_keywords
-- ----------------------------------------






-- Name: toxic_keywords; Type: TABLE; Schema: public; Owner: -

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


-- Name: toxic_keywords_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.toxic_keywords_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: toxic_keywords_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.toxic_keywords_id_seq OWNED BY public.toxic_keywords.id;


-- Name: toxic_keywords id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.toxic_keywords ALTER COLUMN id SET DEFAULT nextval('public.toxic_keywords_id_seq'::regclass);


-- Name: toxic_keywords toxic_keywords_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.toxic_keywords
    ADD CONSTRAINT toxic_keywords_pkey PRIMARY KEY (id);



\unrestrict pj8tCl7C9Hb6Y6EsZIcafSseUaZGFbkme2A8xjLLReIgcIMSRo23YCajc2A96cJ


-- ----------------------------------------
-- Table: tuning_params
-- ----------------------------------------






-- Name: tuning_params; Type: TABLE; Schema: public; Owner: -

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



\unrestrict LS1Q7HRF880SFNkyOlqd6ZOnH8blJ0fd2a0frR4lZdWBpk7U8gTZoqX3hPrn2ZG


-- ----------------------------------------
-- Table: tuning_proposals
-- ----------------------------------------






-- Name: tuning_proposals; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE tuning_proposals; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.tuning_proposals IS 'Auto-generated tuning proposals from feedback analysis. Require admin approval before applying to hot path.';


-- Name: tuning_proposals_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tuning_proposals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tuning_proposals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tuning_proposals_id_seq OWNED BY public.tuning_proposals.id;


-- Name: tuning_proposals id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tuning_proposals ALTER COLUMN id SET DEFAULT nextval('public.tuning_proposals_id_seq'::regclass);


-- Name: idx_tuning_proposals_cat; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_proposals_cat ON public.tuning_proposals USING btree (category, task_type) WHERE (status = 'pending'::text);


-- Name: idx_tuning_proposals_created; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_proposals_created ON public.tuning_proposals USING btree (created_at) WHERE (status = 'pending'::text);


-- Name: idx_tuning_proposals_status; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_proposals_status ON public.tuning_proposals USING btree (status, ts DESC);



\unrestrict LcTUn3uI8HQTfeUUlVnebpOd3YyyqZkAHK4mtS9AmczBCUIbxfSwcUtc0obPveh


-- ----------------------------------------
-- Table: tuning_signals
-- ----------------------------------------






-- Name: tuning_signals; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE tuning_signals; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.tuning_signals IS 'Implicit feedback signals for auto-route tuning. Written async per-request, analyzed daily by feedback_analyzer.';


-- Name: tuning_signals_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tuning_signals_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tuning_signals_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tuning_signals_id_seq OWNED BY public.tuning_signals.id;


-- Name: tuning_signals id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tuning_signals ALTER COLUMN id SET DEFAULT nextval('public.tuning_signals_id_seq'::regclass);


-- Name: idx_tuning_signals_lowq; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_signals_lowq ON public.tuning_signals USING btree (task_type, ts DESC) WHERE ((quality_score < 0.5) AND (classifier = 'heuristic'::text));


-- Name: idx_tuning_signals_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_signals_session ON public.tuning_signals USING btree (session_id, ts DESC) WHERE (session_id IS NOT NULL);


-- Name: idx_tuning_signals_strategy_task; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_signals_strategy_task ON public.tuning_signals USING btree (strategy, task_type, ts DESC) WHERE (task_type IS NOT NULL);


-- Name: idx_tuning_signals_strategy_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_signals_strategy_ts ON public.tuning_signals USING btree (strategy, ts DESC);


-- Name: idx_tuning_signals_task_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tuning_signals_task_ts ON public.tuning_signals USING btree (task_type, ts DESC);



\unrestrict mU8FW1T7hrSq7CQNbcTjSk0O6z5c14rPdc7a1DuShjcuzsJ6bV5VWKY6c2oE83u


-- ----------------------------------------
-- Table: work_type_config
-- ----------------------------------------






-- Name: work_type_config; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE work_type_config; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.work_type_config IS 'Work type definitions (P1 seed; Phase 3 sync from ACC)';


-- Name: work_type_config work_type_config_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.work_type_config
    ADD CONSTRAINT work_type_config_pkey PRIMARY KEY (key);


-- Name: idx_work_type_config_category; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_work_type_config_category ON public.work_type_config USING btree (category, sort_order);


-- Name: idx_work_type_config_l1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_work_type_config_l1 ON public.work_type_config USING btree (l1_task_type);



\unrestrict HypLMhedHsNsJhx351ffBFt0E4K1Qwl6m6v3lLP5iZ7eVafGrI92TSdjJfjhNTN


-- ----------------------------------------
-- Table: work_type_model_route
-- ----------------------------------------






-- Name: work_type_model_route; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE work_type_model_route; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.work_type_model_route IS 'Preferred model routes per work type (L1 selection hints)';


-- Name: COLUMN work_type_model_route.weight; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.work_type_model_route.weight IS '同 tier 内的排序权重（tier 间优先级：primary > secondary > fallback，tier 内按 weight DESC 排）';


-- Name: COLUMN work_type_model_route.tier; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.work_type_model_route.tier IS '三级偏好：primary（首选）/ secondary（次选）/ fallback（兜底）。Index.Recommend 先推荐 primary，全挂时用 secondary，最后才 fallback';


-- Name: COLUMN work_type_model_route.task_quality_score; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.work_type_model_route.task_quality_score IS '该模型在该任务上的人工评分覆盖（0-100）。0 表示用公式计算 scoreStrengthMatch；>0 则直接用该分数';


-- Name: work_type_model_route_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.work_type_model_route_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: work_type_model_route_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.work_type_model_route_id_seq OWNED BY public.work_type_model_route.id;


-- Name: work_type_model_route id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.work_type_model_route ALTER COLUMN id SET DEFAULT nextval('public.work_type_model_route_id_seq'::regclass);


-- Name: work_type_model_route work_type_model_route_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.work_type_model_route
    ADD CONSTRAINT work_type_model_route_pkey PRIMARY KEY (id);


-- Name: work_type_model_route work_type_model_route_work_type_key_canonical_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.work_type_model_route
    ADD CONSTRAINT work_type_model_route_work_type_key_canonical_name_key UNIQUE (work_type_key, canonical_name);


-- Name: idx_wtmr_tier; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_wtmr_tier ON public.work_type_model_route USING btree (work_type_key, tier, weight DESC);


-- Name: idx_wtmr_work_type; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_wtmr_work_type ON public.work_type_model_route USING btree (work_type_key);



\unrestrict bWuXGQXXBKtg0Bowu3Xh8kK2yiYCf7lMsOHkk4YcJYVlxREnkmUQnv1M84M07Hh


