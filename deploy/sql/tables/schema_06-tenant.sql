-- ============================================
-- LLM Gateway Database Schema
-- Category: 06-tenant
-- Generated: 2026-07-05 17:14:34
-- ============================================

-- ----------------------------------------
-- Table: tenant_credit_wallets
-- ----------------------------------------






-- Name: tenant_credit_wallets; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.tenant_credit_wallets (
    tenant_id character varying(64) NOT NULL,
    balance_credits bigint DEFAULT 0 NOT NULL,
    locked_credits bigint DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    granted_balance bigint DEFAULT 0 NOT NULL,
    purchased_balance bigint DEFAULT 0 NOT NULL
);


-- Name: tenant_credit_wallets; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tenant_credit_wallets ENABLE ROW LEVEL SECURITY;

-- Name: tenant_credit_wallets tenant_isolation_tenant_credit_wallets; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tenant_credit_wallets ON public.tenant_credit_wallets USING (((tenant_id)::text = public.get_current_tenant()));



\unrestrict nFJaWrROzOHdAwUe3wopjAt7YSzSE3f5eLtoAe9QgZZy6GmupQqJIx3iSpyRUxq


-- ----------------------------------------
-- Table: tenant_model_policies
-- ----------------------------------------






-- Name: tenant_model_policies; Type: TABLE; Schema: public; Owner: -

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


-- Name: tenant_model_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tenant_model_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tenant_model_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tenant_model_policies_id_seq OWNED BY public.tenant_model_policies.id;


-- Name: tenant_model_policies id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tenant_model_policies ALTER COLUMN id SET DEFAULT nextval('public.tenant_model_policies_id_seq'::regclass);


-- Name: tenant_model_policies tenant_model_policies_tenant_id_canonical_name_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tenant_model_policies
    ADD CONSTRAINT tenant_model_policies_tenant_id_canonical_name_key UNIQUE (tenant_id, canonical_name);


-- Name: idx_tmp_canonical; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tmp_canonical ON public.tenant_model_policies USING btree (canonical_name);


-- Name: idx_tmp_tenant_active; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tmp_tenant_active ON public.tenant_model_policies USING btree (tenant_id) WHERE (deleted_at IS NULL);


-- Name: tenant_model_policies tenant_model_policies_audit_trg; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER tenant_model_policies_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.tenant_model_policies FOR EACH ROW EXECUTE FUNCTION public.tenant_model_policies_audit_fn();


-- Name: tenant_model_policies tenant_isolation_tmp; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tmp ON public.tenant_model_policies USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: tenant_model_policies; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tenant_model_policies ENABLE ROW LEVEL SECURITY;


\unrestrict MnUORJ07OOFqOTAamhCvPCpD0O74LE4vRiA8WKHz9ZkcKaKoS5UZoEtBCATsktZ


-- ----------------------------------------
-- Table: tenant_model_policies_audit
-- ----------------------------------------






-- Name: tenant_model_policies_audit; Type: TABLE; Schema: public; Owner: -

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


-- Name: tenant_model_policies_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tenant_model_policies_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tenant_model_policies_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tenant_model_policies_audit_id_seq OWNED BY public.tenant_model_policies_audit.id;


-- Name: tenant_model_policies_audit id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tenant_model_policies_audit ALTER COLUMN id SET DEFAULT nextval('public.tenant_model_policies_audit_id_seq'::regclass);


-- Name: idx_tmp_audit_tenant_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tmp_audit_tenant_ts ON public.tenant_model_policies_audit USING btree (tenant_id, ts DESC);


-- Name: idx_tmp_audit_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tmp_audit_ts ON public.tenant_model_policies_audit USING btree (ts DESC);


-- Name: tenant_model_policies_audit tenant_isolation_tmp_audit; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tmp_audit ON public.tenant_model_policies_audit USING (((tenant_id = public.get_current_tenant()) OR (tenant_id IS NULL)));


-- Name: tenant_model_policies_audit; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tenant_model_policies_audit ENABLE ROW LEVEL SECURITY;


\unrestrict azglyftGDUOEijZKHykRQ6sCPRpwJ9YQ4XC82XsrcDIKQwtOe4gk4eeR8tfyGSa


-- ----------------------------------------
-- Table: tenant_settings_kv
-- ----------------------------------------






-- Name: tenant_settings_kv; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE tenant_settings_kv; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.tenant_settings_kv IS '租户级运行时设置（Q3）';


-- Name: idx_tenant_settings_kv_category; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tenant_settings_kv_category ON public.tenant_settings_kv USING btree (category);


-- Name: idx_tenant_settings_kv_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tenant_settings_kv_tenant ON public.tenant_settings_kv USING btree (tenant_id);


-- Name: tenant_settings_kv tenant_isolation_tenant_settings_kv; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tenant_settings_kv ON public.tenant_settings_kv USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: tenant_settings_kv; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tenant_settings_kv ENABLE ROW LEVEL SECURITY;


\unrestrict 6FELvwmO49fTu0LZxhOQYXb8XgkY8f88M28iwPac1YkH3I4e3awrhkCjmezUn9S


-- ----------------------------------------
-- Table: tenant_subscriptions
-- ----------------------------------------






-- Name: tenant_subscriptions; Type: TABLE; Schema: public; Owner: -

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


-- Name: tenant_subscriptions_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tenant_subscriptions_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tenant_subscriptions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tenant_subscriptions_id_seq OWNED BY public.tenant_subscriptions.id;


-- Name: tenant_subscriptions id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tenant_subscriptions ALTER COLUMN id SET DEFAULT nextval('public.tenant_subscriptions_id_seq'::regclass);


-- Name: idx_tenant_subscriptions_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tenant_subscriptions_tenant ON public.tenant_subscriptions USING btree (tenant_id, status);


-- Name: tenant_subscriptions tenant_isolation_tenant_subscriptions; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tenant_subscriptions ON public.tenant_subscriptions USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: tenant_subscriptions; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tenant_subscriptions ENABLE ROW LEVEL SECURITY;


\unrestrict No1HPgfQvBISumHT8N7On5UgntmFM7R7XucFiYWBqbIHeQUVMYIGYE2Bchthzbr


-- ----------------------------------------
-- Table: tenant_tool_policies
-- ----------------------------------------






-- Name: tenant_tool_policies; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE tenant_tool_policies; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.tenant_tool_policies IS 'Tenant-level tool access policies (Phase 3.4: 权限控制)';


-- Name: COLUMN tenant_tool_policies.tool_pattern; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tenant_tool_policies.tool_pattern IS 'Tool pattern: exact match (filesystem.read_file) or wildcard (filesystem.*)';


-- Name: COLUMN tenant_tool_policies.policy_type; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tenant_tool_policies.policy_type IS 'Policy type: allow (whitelist) or deny (blacklist)';


-- Name: COLUMN tenant_tool_policies.reason; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.tenant_tool_policies.reason IS 'Reason for this policy (audit trail)';


-- Name: tenant_tool_policies_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.tenant_tool_policies_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: tenant_tool_policies_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.tenant_tool_policies_id_seq OWNED BY public.tenant_tool_policies.id;


-- Name: tenant_tool_policies id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.tenant_tool_policies ALTER COLUMN id SET DEFAULT nextval('public.tenant_tool_policies_id_seq'::regclass);


-- Name: tenant_tool_policies uk_tenant_tool_policy; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tenant_tool_policies
    ADD CONSTRAINT uk_tenant_tool_policy UNIQUE (tenant_id, tool_pattern);


-- Name: idx_tenant_tool_policies_enabled; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tenant_tool_policies_enabled ON public.tenant_tool_policies USING btree (enabled);


-- Name: idx_tenant_tool_policies_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tenant_tool_policies_tenant ON public.tenant_tool_policies USING btree (tenant_id) WHERE (enabled = true);


-- Name: tenant_tool_policies tenant_isolation_tenant_tool_policies; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_tenant_tool_policies ON public.tenant_tool_policies USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: tenant_tool_policies; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.tenant_tool_policies ENABLE ROW LEVEL SECURITY;


\unrestrict EMAGJxCbjWQ9uFagpTvrE6yLqhPVFB18IsciwBbo140QhrOJZKI9ivq1MEECERo


-- ----------------------------------------
-- Table: tenants
-- ----------------------------------------






-- Name: tenants; Type: TABLE; Schema: public; Owner: -

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


-- Name: tenants tenants_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.tenants
    ADD CONSTRAINT tenants_pkey PRIMARY KEY (code);


-- Name: idx_tenants_name; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tenants_name ON public.tenants USING btree (name);


-- Name: idx_tenants_status; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_tenants_status ON public.tenants USING btree (status);



\unrestrict Dvul9XV5tcDPwIbrNbkHHXzrGpYSGZvLmwxvn0TTWbHFHj5pSbasvovdvIpIYIX


