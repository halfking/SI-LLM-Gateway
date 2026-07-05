-- ============================================
-- LLM Gateway Database Schema
-- Category: 08-session
-- Generated: 2026-07-05 17:14:33
-- ============================================

-- ----------------------------------------
-- Table: session_audit_records
-- ----------------------------------------






-- Name: session_audit_records; Type: TABLE; Schema: public; Owner: -

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


-- Name: session_audit_records_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.session_audit_records_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: session_audit_records_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.session_audit_records_id_seq OWNED BY public.session_audit_records.id;


-- Name: session_audit_records id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.session_audit_records ALTER COLUMN id SET DEFAULT nextval('public.session_audit_records_id_seq'::regclass);


-- Name: session_audit_records session_audit_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.session_audit_records
    ADD CONSTRAINT session_audit_records_pkey PRIMARY KEY (id);


-- Name: idx_session_audit_records_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_audit_records_session ON public.session_audit_records USING btree (session_id, created_at DESC);


-- Name: idx_session_audit_records_status; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_audit_records_status ON public.session_audit_records USING btree (status, created_at DESC) WHERE (status = 'need_approval'::text);


-- Name: idx_session_audit_records_tenant_created; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_audit_records_tenant_created ON public.session_audit_records USING btree (tenant_id, created_at DESC);


-- Name: session_audit_records session_audit_records_updated_at; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER session_audit_records_updated_at BEFORE UPDATE ON public.session_audit_records FOR EACH ROW EXECUTE FUNCTION public.trg_session_audit_records_updated_at();


-- Name: session_audit_records; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.session_audit_records ENABLE ROW LEVEL SECURITY;

-- Name: session_audit_records tenant_isolation_session_audit_records; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_session_audit_records ON public.session_audit_records USING (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text)))) WITH CHECK (((COALESCE(NULLIF(current_setting('app.current_role'::text, true), ''::text), ''::text) = 'super_admin'::text) OR (tenant_id = COALESCE(NULLIF(current_setting('app.current_tenant'::text, true), ''::text), 'default'::text))));



\unrestrict oTbeLVhVnEVdudgd16naSbtS7Q5OMQAauJk6nZAY1ZZ4Brz5OytTOAoAqeOew4h


-- ----------------------------------------
-- Table: session_memora_extraction_log
-- ----------------------------------------






-- Name: session_memora_extraction_log; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.session_memora_extraction_log (
    task_id text NOT NULL,
    extracted_at timestamp with time zone DEFAULT now() NOT NULL,
    written integer DEFAULT 0 NOT NULL,
    skipped_noise integer DEFAULT 0 NOT NULL,
    skipped_duplicate integer DEFAULT 0 NOT NULL,
    status text DEFAULT 'ok'::text NOT NULL,
    detail jsonb
);


-- Name: idx_session_memora_extraction_at; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_memora_extraction_at ON public.session_memora_extraction_log USING btree (extracted_at DESC);



\unrestrict re0SGeguMGmQdF5UjB2QN2EK5kw6j68Qi5zDsMcUsT4chQyqCDmt9bUbawVIHae


-- ----------------------------------------
-- Table: session_summaries
-- ----------------------------------------






-- Name: session_summaries; Type: TABLE; Schema: public; Owner: -

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


-- Name: session_summaries session_summaries_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT session_summaries_pkey PRIMARY KEY (session_key);


-- Name: idx_session_summaries_compliance; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_summaries_compliance ON public.session_summaries USING btree (tenant_id, compliance_status) WHERE ((compliance_status)::text <> 'compliant'::text);


-- Name: idx_session_summaries_cost; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_summaries_cost ON public.session_summaries USING btree (tenant_id, total_cost_usd DESC);


-- Name: idx_session_summaries_intent; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_summaries_intent ON public.session_summaries USING btree (tenant_id, user_intent) WHERE (user_intent IS NOT NULL);


-- Name: idx_session_summaries_models; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_summaries_models ON public.session_summaries USING gin (models_used);


-- Name: idx_session_summaries_quality; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_summaries_quality ON public.session_summaries USING btree (quality_score DESC) WHERE (quality_score IS NOT NULL);


-- Name: idx_session_summaries_tenant_time; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_summaries_tenant_time ON public.session_summaries USING btree (tenant_id, last_request_at DESC);


-- Name: idx_session_summaries_topics; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_summaries_topics ON public.session_summaries USING gin (key_topics);


-- Name: session_summaries fk_session_tenant; Type: FK CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.session_summaries
    ADD CONSTRAINT fk_session_tenant FOREIGN KEY (tenant_id) REFERENCES public.tenants(code) ON DELETE CASCADE;


-- Name: session_summaries; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.session_summaries ENABLE ROW LEVEL SECURITY;

-- Name: session_summaries session_summaries_super_admin_bypass; Type: POLICY; Schema: public; Owner: -

CREATE POLICY session_summaries_super_admin_bypass ON public.session_summaries USING (((current_setting('app.current_role'::text, true) = 'super_admin'::text) OR (current_setting('app.bypass_rls'::text, true) = 'true'::text)));


-- Name: session_summaries session_summaries_tenant_isolation; Type: POLICY; Schema: public; Owner: -

CREATE POLICY session_summaries_tenant_isolation ON public.session_summaries USING (((tenant_id)::text = current_setting('app.current_tenant'::text, true)));



\unrestrict DAxHnZ6AMadDXt3H9U79E8Po0euTgLQ4Hl5RzxhEL5UXfkDrKUJbbZMaWMIoJJG


-- ----------------------------------------
-- Table: session_titles
-- ----------------------------------------






-- Name: session_titles; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.session_titles (
    task_id text NOT NULL,
    scoped_session_id text DEFAULT ''::text NOT NULL,
    title text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    model text,
    api_key_id integer
);


-- Name: idx_session_titles_generated_at; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_session_titles_generated_at ON public.session_titles USING btree (generated_at DESC);



\unrestrict 1LXWvXjmhIVy8VahzcEhFYdNgAXVgnFdtp7xdtUjJBKHndZuXBcb2vA9dUSVqQG


