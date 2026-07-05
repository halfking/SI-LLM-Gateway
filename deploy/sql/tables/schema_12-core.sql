-- ============================================
-- LLM Gateway Database Schema
-- Category: 12-core
-- Generated: 2026-07-05 17:14:29
-- ============================================

-- ----------------------------------------
-- Table: agents
-- ----------------------------------------






-- Name: agents; Type: TABLE; Schema: public; Owner: -

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


-- Name: agents_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.agents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: agents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.agents_id_seq OWNED BY public.agents.id;


-- Name: agents id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.agents ALTER COLUMN id SET DEFAULT nextval('public.agents_id_seq'::regclass);


-- Name: agents agents_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.agents
    ADD CONSTRAINT agents_pkey PRIMARY KEY (id);


-- Name: idx_agents_capabilities; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_agents_capabilities ON public.agents USING gin (capabilities jsonb_path_ops);


-- Name: idx_agents_heartbeat; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_agents_heartbeat ON public.agents USING btree (last_heartbeat) WHERE (last_heartbeat IS NOT NULL);


-- Name: idx_agents_kind; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_agents_kind ON public.agents USING btree (tenant_id, kind);


-- Name: idx_agents_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_agents_tenant ON public.agents USING btree (tenant_id);


-- Name: agents; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.agents ENABLE ROW LEVEL SECURITY;

-- Name: agents tenant_isolation_agents; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_agents ON public.agents USING ((tenant_id = public.get_current_tenant()));



\unrestrict UUae3FRxWIiLnzLGFbQTsrr3rHM2iv3oY9kFCBLXhE29NEWgXO5nk0vGRq7bN0g


-- ----------------------------------------
-- Table: applications
-- ----------------------------------------






-- Name: applications; Type: TABLE; Schema: public; Owner: -

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


-- Name: applications_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.applications_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: applications_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.applications_id_seq OWNED BY public.applications.id;


-- Name: applications id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.applications ALTER COLUMN id SET DEFAULT nextval('public.applications_id_seq'::regclass);


-- Name: applications applications_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_pkey PRIMARY KEY (id);


-- Name: applications applications_tenant_id_code_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.applications
    ADD CONSTRAINT applications_tenant_id_code_key UNIQUE (tenant_id, code);


-- Name: idx_applications_tenant_code; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_applications_tenant_code ON public.applications USING btree (tenant_id, code) WHERE (enabled = true);



\unrestrict wBrdsDR4OU5wPPkdKmVRLwe3rp8SbrY2fA3YCFwnenx47C1Yv5EnQCvM6oJGajo


-- ----------------------------------------
-- Table: attachments
-- ----------------------------------------






-- Name: attachments; Type: TABLE; Schema: public; Owner: -

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


-- Name: attachments attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.attachments
    ADD CONSTRAINT attachments_pkey PRIMARY KEY (id);


-- Name: idx_attachments_hash; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_attachments_hash ON public.attachments USING btree (content_hash, tenant_id);


-- Name: idx_attachments_request; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_attachments_request ON public.attachments USING btree (request_id);


-- Name: idx_attachments_tenant_created; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_attachments_tenant_created ON public.attachments USING btree (tenant_id, created_at DESC);


-- Name: attachments; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.attachments ENABLE ROW LEVEL SECURITY;

-- Name: attachments tenant_isolation_attachments; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_attachments ON public.attachments USING ((tenant_id = public.get_current_tenant()));



\unrestrict DzJbNBuHrW7yy3ibcMhPNLcRP5lcdxlOemY50XjRgVslCs7exuWJanT6YggvfAi


-- ----------------------------------------
-- Table: users
-- ----------------------------------------






-- Name: users; Type: TABLE; Schema: public; Owner: -

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


-- Name: users_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.users_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: users_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.users_id_seq OWNED BY public.users.id;


-- Name: users id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.users ALTER COLUMN id SET DEFAULT nextval('public.users_id_seq'::regclass);


-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


-- Name: users users_username_key; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_username_key UNIQUE (username);


-- Name: idx_users_tenant; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_users_tenant ON public.users USING btree (tenant_id);


-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_users_username ON public.users USING btree (username);


-- Name: users tenant_isolation_users; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_users ON public.users USING (((tenant_id)::text = public.get_current_tenant()));


-- Name: users; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;


\unrestrict 1KyGihgclwUx2FS4zXbRbqgMOLvJgLDl7lKo7NUXJ0KP5E98r949p8rSPn2cjlj


