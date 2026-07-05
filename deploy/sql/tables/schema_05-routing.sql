-- ============================================
-- LLM Gateway Database Schema
-- Category: 05-routing
-- Generated: 2026-07-05 17:14:27
-- ============================================

-- ----------------------------------------
-- Table: routing_audit_log
-- ----------------------------------------






-- Name: routing_audit_log; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_audit_log_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.routing_audit_log_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: routing_audit_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.routing_audit_log_id_seq OWNED BY public.routing_audit_log.id;


-- Name: routing_audit_log id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.routing_audit_log ALTER COLUMN id SET DEFAULT nextval('public.routing_audit_log_id_seq'::regclass);



\unrestrict 3JOpLHhskiMbgm55Rhw3kNzypk22VPTOmcXbtikbPmlCrE69NmEiTlDYdGXLGdm


-- ----------------------------------------
-- Table: routing_decision_log
-- ----------------------------------------





-- Name: routing_decision_log; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE routing_decision_log; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.routing_decision_log IS 'Routing decision logs - partitioned by month (RANGE on ts). Current month uses heap storage. Historical months are archived to routing_decision_log_archive (columnar) via archive_routing_decision_log() function. Call this monthly on day 1.';


-- Name: idx_routing_decision_log_part_credential; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_decision_log_part_credential ON ONLY public.routing_decision_log USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


-- Name: idx_routing_decision_log_part_model; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_decision_log_part_model ON ONLY public.routing_decision_log USING btree (model, ts DESC);


-- Name: idx_routing_decision_log_part_request_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_decision_log_part_request_id ON ONLY public.routing_decision_log USING btree (request_id);


-- Name: idx_routing_decision_log_part_success; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_decision_log_part_success ON ONLY public.routing_decision_log USING btree (success, ts DESC);


-- Name: idx_routing_decision_log_part_tenant_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_decision_log_part_tenant_ts ON ONLY public.routing_decision_log USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


-- Name: idx_routing_decision_log_part_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_decision_log_part_ts ON ONLY public.routing_decision_log USING btree (ts DESC);



\unrestrict DDwe2KZRl9qi8DLLXe8m3gitLsDCiThXiPkdojlv2kRoxJEr2K6NOLczEGzbpnz


-- ----------------------------------------
-- Table: routing_decision_log_2026_07
-- ----------------------------------------






-- Name: routing_decision_log_2026_07; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_decision_log_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


-- Name: routing_decision_log_2026_07_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_07_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


-- Name: routing_decision_log_2026_07_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_07_model_ts_idx ON public.routing_decision_log_2026_07 USING btree (model, ts DESC);


-- Name: routing_decision_log_2026_07_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_07_request_id_idx ON public.routing_decision_log_2026_07 USING btree (request_id);


-- Name: routing_decision_log_2026_07_success_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_07_success_ts_idx ON public.routing_decision_log_2026_07 USING btree (success, ts DESC);


-- Name: routing_decision_log_2026_07_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_07_tenant_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


-- Name: routing_decision_log_2026_07_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_07_ts_idx ON public.routing_decision_log_2026_07 USING btree (ts DESC);


-- Name: routing_decision_log_2026_07_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_07_chosen_credential_id_ts_idx;


-- Name: routing_decision_log_2026_07_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_07_model_ts_idx;


-- Name: routing_decision_log_2026_07_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_07_request_id_idx;


-- Name: routing_decision_log_2026_07_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_07_success_ts_idx;


-- Name: routing_decision_log_2026_07_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_07_tenant_id_ts_idx;


-- Name: routing_decision_log_2026_07_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_07_ts_idx;



\unrestrict 3jfm5RdChKKwD5gsyqhvMnvH2T7QN9RYX0blagSWwSkS7e7vneTnHKobePu0hHd


-- ----------------------------------------
-- Table: routing_decision_log_2026_08
-- ----------------------------------------






-- Name: routing_decision_log_2026_08; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_decision_log_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


-- Name: routing_decision_log_2026_08_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_08_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_08 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


-- Name: routing_decision_log_2026_08_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_08_model_ts_idx ON public.routing_decision_log_2026_08 USING btree (model, ts DESC);


-- Name: routing_decision_log_2026_08_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_08_request_id_idx ON public.routing_decision_log_2026_08 USING btree (request_id);


-- Name: routing_decision_log_2026_08_success_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_08_success_ts_idx ON public.routing_decision_log_2026_08 USING btree (success, ts DESC);


-- Name: routing_decision_log_2026_08_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_08_tenant_id_ts_idx ON public.routing_decision_log_2026_08 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


-- Name: routing_decision_log_2026_08_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_2026_08_ts_idx ON public.routing_decision_log_2026_08 USING btree (ts DESC);


-- Name: routing_decision_log_2026_08_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_08_chosen_credential_id_ts_idx;


-- Name: routing_decision_log_2026_08_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_08_model_ts_idx;


-- Name: routing_decision_log_2026_08_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_08_request_id_idx;


-- Name: routing_decision_log_2026_08_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_08_success_ts_idx;


-- Name: routing_decision_log_2026_08_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_08_tenant_id_ts_idx;


-- Name: routing_decision_log_2026_08_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_08_ts_idx;



\unrestrict 5h5gCc1T4q8aI3B4pSVj2FHg0gQeQmURDWZedGVjLveaC0baH2VTtPy7NheSmgv


-- ----------------------------------------
-- Table: routing_decision_log_archive
-- ----------------------------------------





-- Name: routing_decision_log_archive; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_decision_log_archive; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.routing_decision_log_archive ENABLE ROW LEVEL SECURITY;

-- Name: routing_decision_log_archive tenant_isolation_routing_decision_log_archive; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive USING ((tenant_id = public.get_current_tenant()));



\unrestrict Oy3irUGHbwkcB9UNJtRkXd77cOGqVSqjyJvqbE32gL3VUWuKvUFDMgMot3Ha2xf


-- ----------------------------------------
-- Table: routing_decision_log_archive_2026_08
-- ----------------------------------------






-- Name: routing_decision_log_archive_2026_08; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_decision_log_archive_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.routing_decision_log_archive ATTACH PARTITION public.routing_decision_log_archive_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



\unrestrict ktiYzsJiZf4y9cQMTZQhYoiLxD7gqoAHohFoVIYuT8BHJf0GmVSaOanSEp2dsc8


-- ----------------------------------------
-- Table: routing_decision_log_default
-- ----------------------------------------






-- Name: routing_decision_log_default; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_decision_log_default; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_default DEFAULT;


-- Name: routing_decision_log_default_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_default_chosen_credential_id_ts_idx ON public.routing_decision_log_default USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


-- Name: routing_decision_log_default_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_default_model_ts_idx ON public.routing_decision_log_default USING btree (model, ts DESC);


-- Name: routing_decision_log_default_request_id_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_default_request_id_idx ON public.routing_decision_log_default USING btree (request_id);


-- Name: routing_decision_log_default_success_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_default_success_ts_idx ON public.routing_decision_log_default USING btree (success, ts DESC);


-- Name: routing_decision_log_default_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_default_tenant_id_ts_idx ON public.routing_decision_log_default USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


-- Name: routing_decision_log_default_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX routing_decision_log_default_ts_idx ON public.routing_decision_log_default USING btree (ts DESC);


-- Name: routing_decision_log_default_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_default_chosen_credential_id_ts_idx;


-- Name: routing_decision_log_default_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_default_model_ts_idx;


-- Name: routing_decision_log_default_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_default_request_id_idx;


-- Name: routing_decision_log_default_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_default_success_ts_idx;


-- Name: routing_decision_log_default_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_default_tenant_id_ts_idx;


-- Name: routing_decision_log_default_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_default_ts_idx;



\unrestrict e5rpyD8ZgS92xnS5EwrdTZhWAph2LJUCEOrRTfue4y6OViWDP9NtjITbCkh5GPZ


-- ----------------------------------------
-- Table: routing_decision_log_old
-- ----------------------------------------






-- Name: routing_decision_log_old; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE routing_decision_log_old; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.routing_decision_log_old IS 'DEPRECATED: Old non-partitioned routing_decision_log table. Verify routing_decision_log works correctly, then DROP TABLE routing_decision_log_old;';



\unrestrict MSmQFZBrD5b9aKXWJLMS5J0Zyto2VCMmKaKpYBQ40QI9n7A1DlakmIWOk2xS847


-- ----------------------------------------
-- Table: routing_overrides
-- ----------------------------------------






-- Name: routing_overrides; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_overrides_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.routing_overrides_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: routing_overrides_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.routing_overrides_id_seq OWNED BY public.routing_overrides.id;


-- Name: routing_overrides id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.routing_overrides ALTER COLUMN id SET DEFAULT nextval('public.routing_overrides_id_seq'::regclass);


-- Name: idx_routing_overrides_expires; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_overrides_expires ON public.routing_overrides USING btree (expires_at) WHERE (expires_at IS NOT NULL);


-- Name: idx_routing_overrides_task_profile; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_overrides_task_profile ON public.routing_overrides USING btree (task_type, profile);


-- Name: idx_routing_overrides_unique; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX idx_routing_overrides_unique ON public.routing_overrides USING btree (task_type, profile, COALESCE(model_chosen, ''::text), mode);


-- Name: routing_overrides routing_overrides_audit_trg; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER routing_overrides_audit_trg AFTER INSERT OR DELETE OR UPDATE ON public.routing_overrides FOR EACH ROW EXECUTE FUNCTION public.routing_overrides_audit_fn();



\unrestrict Ib7zgiebyI6o3FLomlwRkHCl8uPtX9FYAuHIxh5VgvTOHSEGbinZPlgTGEMPOvL


-- ----------------------------------------
-- Table: routing_overrides_audit
-- ----------------------------------------






-- Name: routing_overrides_audit; Type: TABLE; Schema: public; Owner: -

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


-- Name: routing_overrides_audit_id_seq; Type: SEQUENCE; Schema: public; Owner: -

CREATE SEQUENCE public.routing_overrides_audit_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


-- Name: routing_overrides_audit_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -

ALTER SEQUENCE public.routing_overrides_audit_id_seq OWNED BY public.routing_overrides_audit.id;


-- Name: routing_overrides_audit id; Type: DEFAULT; Schema: public; Owner: -

ALTER TABLE ONLY public.routing_overrides_audit ALTER COLUMN id SET DEFAULT nextval('public.routing_overrides_audit_id_seq'::regclass);


-- Name: idx_routing_overrides_audit_actor_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_overrides_audit_actor_ts ON public.routing_overrides_audit USING btree (actor, ts DESC) WHERE (actor IS NOT NULL);


-- Name: idx_routing_overrides_audit_override_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_overrides_audit_override_ts ON public.routing_overrides_audit USING btree (override_id, ts DESC) WHERE (override_id IS NOT NULL);


-- Name: idx_routing_overrides_audit_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_routing_overrides_audit_ts ON public.routing_overrides_audit USING btree (ts DESC);



\unrestrict pzqMzavHz2tp71xY15k2JeklOK0Yz4ujxS9woL6L5fQABMPf6JrEcDPh5nOIl6R


-- ----------------------------------------
-- Table: routing_policy
-- ----------------------------------------






-- Name: routing_policy; Type: TABLE; Schema: public; Owner: -

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



\unrestrict 6GRijnuGq1jGUJSI0CU0Gzudj59VRBdJjnygxxB5o5t7t4wOnzSOr4RhdhYfUeY


