-- ============================================
-- LLM Gateway Database Schema
-- Category: 11-audit
-- Generated: 2026-07-05 17:14:31
-- ============================================

-- ----------------------------------------
-- Table: auto_tune_audit
-- ----------------------------------------






-- Name: auto_tune_audit; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE auto_tune_audit; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.auto_tune_audit IS 'Audit log for concurrency limit auto-tune actions (24h preview + auto-apply)';


-- Name: auto_tune_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.auto_tune_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: auto_tune_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.auto_tune_audit_id_seq OWNED BY public.auto_tune_audit.id;


-- Name: auto_tune_audit id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.auto_tune_audit ALTER COLUMN id SET DEFAULT nextval('public.auto_tune_audit_id_seq'::regclass);



\unrestrict GP3KF1jqxcX8qJJWfOLrSopBg4hv9D9uilaef8MzEsYK0xJywhDIxFBnRguwh03


-- ----------------------------------------
-- Table: candidate_failure_logs
-- ----------------------------------------






-- Name: candidate_failure_logs; Type: TABLE; Schema: public; Owner: -

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


-- Name: COLUMN candidate_failure_logs.per_attempt_latency_ms; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.candidate_failure_logs.per_attempt_latency_ms IS 'Latency of the single upstream call.';



\unrestrict fW1NRNuiPYwMhjIQk0P6AYMI9OaJnYUErUvXPeZQO9DiDFeCQGZiYuXRwcamXqc


-- ----------------------------------------
-- Table: handoff_logs
-- ----------------------------------------






-- Name: handoff_logs; Type: TABLE; Schema: public; Owner: -

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


-- Name: handoff_logs_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.handoff_logs_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: handoff_logs_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.handoff_logs_id_seq OWNED BY public.handoff_logs.id;


-- Name: handoff_logs id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.handoff_logs ALTER COLUMN id SET DEFAULT nextval('public.handoff_logs_id_seq'::regclass);


-- Name: handoff_logs handoff_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.handoff_logs
    ADD CONSTRAINT handoff_logs_pkey PRIMARY KEY (id);


-- Name: idx_handoff_logs_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_handoff_logs_session ON public.handoff_logs USING btree (session_id, created_at DESC);


-- Name: idx_handoff_logs_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_handoff_logs_tenant ON public.handoff_logs USING btree (tenant_id, created_at DESC);



\unrestrict FgtsSssF1kuBJiHfHZ2aTcXHqF3eSpVHQDGwRVjtXR7KiTSkugc5SRcoknVuhMJ


-- ----------------------------------------
-- Table: output_compliance_audit
-- ----------------------------------------






-- Name: output_compliance_audit; Type: TABLE; Schema: public; Owner: -

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


-- Name: output_compliance_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.output_compliance_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: output_compliance_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.output_compliance_audit_id_seq OWNED BY public.output_compliance_audit.id;


-- Name: output_compliance_audit id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.output_compliance_audit ALTER COLUMN id SET DEFAULT nextval('public.output_compliance_audit_id_seq'::regclass);


-- Name: output_compliance_audit output_compliance_audit_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.output_compliance_audit
    ADD CONSTRAINT output_compliance_audit_pkey PRIMARY KEY (id);


-- Name: idx_output_audit_issue; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_output_audit_issue ON public.output_compliance_audit USING btree (tenant_id, issue_type, severity DESC);


-- Name: idx_output_audit_request; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_output_audit_request ON public.output_compliance_audit USING btree (request_id);


-- Name: idx_output_audit_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_output_audit_session ON public.output_compliance_audit USING btree (session_key);


-- Name: idx_output_audit_tenant_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_output_audit_tenant_time ON public.output_compliance_audit USING btree (tenant_id, detected_at DESC);


-- Name: output_compliance_audit; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.output_compliance_audit ENABLE ROW LEVEL SECURITY;

-- Name: output_compliance_audit output_compliance_audit_super_admin; Type: POLICY; Schema: public; Owner: -

CREATE POLICY output_compliance_audit_super_admin ON public.output_compliance_audit USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


-- Name: output_compliance_audit output_compliance_audit_tenant; Type: POLICY; Schema: public; Owner: -

CREATE POLICY output_compliance_audit_tenant ON public.output_compliance_audit USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



\unrestrict HvFCRBGvaOmpRWc0NUnItuhqJcvzZP7Jf4UpjjwuZh9BEYfsexp0InbrPY9GnO3


-- ----------------------------------------
-- Table: pricing_refresh_log
-- ----------------------------------------






-- Name: pricing_refresh_log; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE pricing_refresh_log; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.pricing_refresh_log IS 'Audit log for monthly pricing refresh cron job. Each run inserts one row.';


-- Name: COLUMN pricing_refresh_log.before_summary; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.pricing_refresh_log.before_summary IS 'pricing/summary response BEFORE refresh (pricing_plans + cmb state)';


-- Name: COLUMN pricing_refresh_log.after_summary; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.pricing_refresh_log.after_summary IS 'pricing/summary response AFTER refresh';


-- Name: COLUMN pricing_refresh_log.diff_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.pricing_refresh_log.diff_count IS 'Total offers changed (new + removed + changed)';


-- Name: COLUMN pricing_refresh_log.artifacts_path; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.pricing_refresh_log.artifacts_path IS 'PVC path containing fetch.log, tier-pricing.csv, summary_*.json';


-- Name: pricing_refresh_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.pricing_refresh_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: pricing_refresh_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.pricing_refresh_log_id_seq OWNED BY public.pricing_refresh_log.id;


-- Name: pricing_refresh_log id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.pricing_refresh_log ALTER COLUMN id SET DEFAULT nextval('public.pricing_refresh_log_id_seq'::regclass);



\unrestrict djEDniJNapeuDbeewkRE1abOoqXi9GraoEHKgSvTgYx1hZPw23RVT6NQj73upWe


-- ----------------------------------------
-- Table: schema_migration_audit
-- ----------------------------------------






-- Name: schema_migration_audit; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.schema_migration_audit (
    migration_id text NOT NULL,
    applied_at timestamp with time zone DEFAULT now() NOT NULL,
    row_count bigint DEFAULT 0 NOT NULL,
    note text DEFAULT ''::text NOT NULL
);



\unrestrict jCRkGYbrvh8PydWPMrVmjcqOPUPge1INtLCzKTXGO2gUmQEUMtQkQaCbEv87LCu


-- ----------------------------------------
-- Table: security_audit_log
-- ----------------------------------------






-- Name: security_audit_log; Type: TABLE; Schema: public; Owner: -

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


-- Name: security_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.security_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: security_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.security_audit_log_id_seq OWNED BY public.security_audit_log.id;


-- Name: security_audit_log id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.security_audit_log ALTER COLUMN id SET DEFAULT nextval('public.security_audit_log_id_seq'::regclass);



\unrestrict fKkCrqboSRirtoPaNrfEWinbG8PB1GHKHojimMl8IP8qYTuffMUjl6ywqQ02oWa


-- ----------------------------------------
-- Table: settings_audit
-- ----------------------------------------






-- Name: settings_audit; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE settings_audit; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.settings_audit IS '设置修改审计日志（bg/settings_audit_cleaner.go 每 24h 清理 7 天前的数据）';


-- Name: COLUMN settings_audit.action; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.settings_audit.action IS 'update / rollback / delete';


-- Name: settings_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.settings_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: settings_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.settings_audit_id_seq OWNED BY public.settings_audit.id;


-- Name: settings_audit id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.settings_audit ALTER COLUMN id SET DEFAULT nextval('public.settings_audit_id_seq'::regclass);


-- Name: idx_settings_audit_created; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_settings_audit_created ON public.settings_audit USING btree (created_at);


-- Name: idx_settings_audit_key_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_settings_audit_key_time ON public.settings_audit USING btree (setting_key, created_at DESC);


-- Name: idx_settings_audit_operator; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_settings_audit_operator ON public.settings_audit USING btree (operator_user, created_at DESC);


-- Name: idx_settings_audit_tenant_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_settings_audit_tenant_time ON public.settings_audit USING btree (tenant_id, created_at DESC);


-- Name: settings_audit; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.settings_audit ENABLE ROW LEVEL SECURITY;

-- Name: settings_audit tenant_isolation_settings_audit; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_settings_audit ON public.settings_audit USING ((((tenant_id)::text = public.get_current_tenant()) OR (tenant_id IS NULL)));



\unrestrict cm10nCbttIcqQ6Q3593wB3nWMdz5hck3Nx791Cp4heytQEDU0bOzYG76U8HxrcY


-- ----------------------------------------
-- Table: token_audit_events
-- ----------------------------------------






-- Name: token_audit_events; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.token_audit_events (
    id bigint NOT NULL,
    request_id text NOT NULL,
    credential_id bigint NOT NULL,
    claimed_tokens integer,
    estimated_tokens integer,
    delta_pct numeric(6,3),
    ts timestamp with time zone DEFAULT now() NOT NULL
);


-- Name: token_audit_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.token_audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: token_audit_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.token_audit_events_id_seq OWNED BY public.token_audit_events.id;


-- Name: token_audit_events id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.token_audit_events ALTER COLUMN id SET DEFAULT nextval('public.token_audit_events_id_seq'::regclass);



\unrestrict l8DWs7o06ulmsJOA5J5MxzcrI3hDVpxwnBuRPtL3XTDrbBkgActnpfq3i1BHqgR


