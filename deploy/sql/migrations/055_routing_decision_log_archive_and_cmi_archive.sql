-- Migration: Add new objects from production schema sync
-- Generated from prod-pg pg_dump on 2026-06-30
-- Objects added: 70 (7 tables, 4 TABLE ATTACH, 30 INDEX, 21 INDEX ATTACH, 6 FUNCTION, 1 ROW SECURITY, 1 POLICY)

BEGIN;

-- ========================================
-- TABLE: 7 new objects
-- ========================================

-- ----- Object: credential_model_index_archive (TABLE) -----
-- Name: credential_model_index_archive; Type: TABLE; Schema: public; Owner: -
--

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


SET default_table_access_method = columnar;

--

-- ----- Object: credential_model_index_archive_2026_06 (TABLE) -----
-- Name: credential_model_index_archive_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_index_archive_2026_06 (
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


SET default_table_access_method = heap;

--

-- ----- Object: routing_decision_log_2026_06 (TABLE) -----
-- Name: routing_decision_log_2026_06; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.routing_decision_log_2026_06 (
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


--

-- ----- Object: routing_decision_log_2026_07 (TABLE) -----
-- Name: routing_decision_log_2026_07; Type: TABLE; Schema: public; Owner: -
--

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


--

-- ----- Object: routing_decision_log_archive (TABLE) -----
-- Name: routing_decision_log_archive; Type: TABLE; Schema: public; Owner: -
--

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


--

-- ----- Object: routing_decision_log_default (TABLE) -----
-- Name: routing_decision_log_default; Type: TABLE; Schema: public; Owner: -
--

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


--

-- ----- Object: routing_decision_log_old (TABLE) -----
-- Name: routing_decision_log_old; Type: TABLE; Schema: public; Owner: -
--

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


--

-- ========================================
-- TABLE ATTACH: 4 new objects
-- ========================================

-- ----- Object: credential_model_index_archive_2026_06 (TABLE ATTACH) -----
-- Name: credential_model_index_archive_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_model_index_archive ATTACH PARTITION public.credential_model_index_archive_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--

-- ----- Object: routing_decision_log_2026_06 (TABLE ATTACH) -----
-- Name: routing_decision_log_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--

-- ----- Object: routing_decision_log_2026_07 (TABLE ATTACH) -----
-- Name: routing_decision_log_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


--

-- ----- Object: routing_decision_log_default (TABLE ATTACH) -----
-- Name: routing_decision_log_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_default DEFAULT;


--

-- ========================================
-- INDEX: 30 new objects
-- ========================================

-- ----- Object: credential_model_index_archiv_credential_id_raw_model_bucke_idx (INDEX) -----
-- Name: credential_model_index_archiv_credential_id_raw_model_bucke_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credential_model_index_archiv_credential_id_raw_model_bucke_idx ON public.credential_model_index_archive_2026_06 USING btree (credential_id, raw_model, bucket DESC);


--

-- ----- Object: credential_model_index_archive_2026_06_bucket_idx (INDEX) -----
-- Name: credential_model_index_archive_2026_06_bucket_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credential_model_index_archive_2026_06_bucket_idx ON public.credential_model_index_archive_2026_06 USING btree (bucket DESC);


--

-- ----- Object: credential_model_index_archive_2026_06_canonical_id_bucket_idx (INDEX) -----
-- Name: credential_model_index_archive_2026_06_canonical_id_bucket_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credential_model_index_archive_2026_06_canonical_id_bucket_idx ON public.credential_model_index_archive_2026_06 USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);


--

-- ----- Object: idx_cmi_archive_bucket (INDEX) -----
-- Name: idx_cmi_archive_bucket; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_bucket ON ONLY public.credential_model_index_archive USING btree (bucket DESC);


--

-- ----- Object: idx_cmi_archive_canonical (INDEX) -----
-- Name: idx_cmi_archive_canonical; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_canonical ON ONLY public.credential_model_index_archive USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);


--

-- ----- Object: idx_cmi_archive_cred_model (INDEX) -----
-- Name: idx_cmi_archive_cred_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_cred_model ON ONLY public.credential_model_index_archive USING btree (credential_id, raw_model, bucket DESC);


--

-- ----- Object: idx_routing_decision_log_part_credential (INDEX) -----
-- Name: idx_routing_decision_log_part_credential; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_credential ON ONLY public.routing_decision_log USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--

-- ----- Object: idx_routing_decision_log_part_model (INDEX) -----
-- Name: idx_routing_decision_log_part_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_model ON ONLY public.routing_decision_log USING btree (model, ts DESC);


--

-- ----- Object: idx_routing_decision_log_part_request_id (INDEX) -----
-- Name: idx_routing_decision_log_part_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_request_id ON ONLY public.routing_decision_log USING btree (request_id);


--

-- ----- Object: idx_routing_decision_log_part_success (INDEX) -----
-- Name: idx_routing_decision_log_part_success; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_success ON ONLY public.routing_decision_log USING btree (success, ts DESC);


--

-- ----- Object: idx_routing_decision_log_part_tenant_ts (INDEX) -----
-- Name: idx_routing_decision_log_part_tenant_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_tenant_ts ON ONLY public.routing_decision_log USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--

-- ----- Object: idx_routing_decision_log_part_ts (INDEX) -----
-- Name: idx_routing_decision_log_part_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_decision_log_part_ts ON ONLY public.routing_decision_log USING btree (ts DESC);


--

-- ----- Object: routing_decision_log_2026_06_chosen_credential_id_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_06_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_06 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--

-- ----- Object: routing_decision_log_2026_06_model_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_06_model_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_model_ts_idx ON public.routing_decision_log_2026_06 USING btree (model, ts DESC);


--

-- ----- Object: routing_decision_log_2026_06_request_id_idx (INDEX) -----
-- Name: routing_decision_log_2026_06_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_request_id_idx ON public.routing_decision_log_2026_06 USING btree (request_id);


--

-- ----- Object: routing_decision_log_2026_06_success_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_06_success_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_success_ts_idx ON public.routing_decision_log_2026_06 USING btree (success, ts DESC);


--

-- ----- Object: routing_decision_log_2026_06_tenant_id_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_06_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_tenant_id_ts_idx ON public.routing_decision_log_2026_06 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--

-- ----- Object: routing_decision_log_2026_06_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_06_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_ts_idx ON public.routing_decision_log_2026_06 USING btree (ts DESC);


--

-- ----- Object: routing_decision_log_2026_07_chosen_credential_id_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_07_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--

-- ----- Object: routing_decision_log_2026_07_model_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_07_model_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_model_ts_idx ON public.routing_decision_log_2026_07 USING btree (model, ts DESC);


--

-- ----- Object: routing_decision_log_2026_07_request_id_idx (INDEX) -----
-- Name: routing_decision_log_2026_07_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_request_id_idx ON public.routing_decision_log_2026_07 USING btree (request_id);


--

-- ----- Object: routing_decision_log_2026_07_success_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_07_success_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_success_ts_idx ON public.routing_decision_log_2026_07 USING btree (success, ts DESC);


--

-- ----- Object: routing_decision_log_2026_07_tenant_id_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_07_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_tenant_id_ts_idx ON public.routing_decision_log_2026_07 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--

-- ----- Object: routing_decision_log_2026_07_ts_idx (INDEX) -----
-- Name: routing_decision_log_2026_07_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_07_ts_idx ON public.routing_decision_log_2026_07 USING btree (ts DESC);


--

-- ----- Object: routing_decision_log_default_chosen_credential_id_ts_idx (INDEX) -----
-- Name: routing_decision_log_default_chosen_credential_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_chosen_credential_id_ts_idx ON public.routing_decision_log_default USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);


--

-- ----- Object: routing_decision_log_default_model_ts_idx (INDEX) -----
-- Name: routing_decision_log_default_model_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_model_ts_idx ON public.routing_decision_log_default USING btree (model, ts DESC);


--

-- ----- Object: routing_decision_log_default_request_id_idx (INDEX) -----
-- Name: routing_decision_log_default_request_id_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_request_id_idx ON public.routing_decision_log_default USING btree (request_id);


--

-- ----- Object: routing_decision_log_default_success_ts_idx (INDEX) -----
-- Name: routing_decision_log_default_success_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_success_ts_idx ON public.routing_decision_log_default USING btree (success, ts DESC);


--

-- ----- Object: routing_decision_log_default_tenant_id_ts_idx (INDEX) -----
-- Name: routing_decision_log_default_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_tenant_id_ts_idx ON public.routing_decision_log_default USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--

-- ----- Object: routing_decision_log_default_ts_idx (INDEX) -----
-- Name: routing_decision_log_default_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_default_ts_idx ON public.routing_decision_log_default USING btree (ts DESC);


--

-- ========================================
-- INDEX ATTACH: 21 new objects
-- ========================================

-- ----- Object: credential_model_index_archiv_credential_id_raw_model_bucke_idx (INDEX ATTACH) -----
-- Name: credential_model_index_archiv_credential_id_raw_model_bucke_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_cred_model ATTACH PARTITION public.credential_model_index_archiv_credential_id_raw_model_bucke_idx;


--

-- ----- Object: credential_model_index_archive_2026_06_bucket_idx (INDEX ATTACH) -----
-- Name: credential_model_index_archive_2026_06_bucket_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_bucket ATTACH PARTITION public.credential_model_index_archive_2026_06_bucket_idx;


--

-- ----- Object: credential_model_index_archive_2026_06_canonical_id_bucket_idx (INDEX ATTACH) -----
-- Name: credential_model_index_archive_2026_06_canonical_id_bucket_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_cmi_archive_canonical ATTACH PARTITION public.credential_model_index_archive_2026_06_canonical_id_bucket_idx;


--

-- ----- Object: routing_decision_log_2026_06_chosen_credential_id_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_06_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_06_chosen_credential_id_ts_idx;


--

-- ----- Object: routing_decision_log_2026_06_model_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_06_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_06_model_ts_idx;


--

-- ----- Object: routing_decision_log_2026_06_request_id_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_06_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_06_request_id_idx;


--

-- ----- Object: routing_decision_log_2026_06_success_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_06_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_06_success_ts_idx;


--

-- ----- Object: routing_decision_log_2026_06_tenant_id_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_06_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_06_tenant_id_ts_idx;


--

-- ----- Object: routing_decision_log_2026_06_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_06_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_06_ts_idx;


--

-- ----- Object: routing_decision_log_2026_07_chosen_credential_id_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_07_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_07_chosen_credential_id_ts_idx;


--

-- ----- Object: routing_decision_log_2026_07_model_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_07_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_2026_07_model_ts_idx;


--

-- ----- Object: routing_decision_log_2026_07_request_id_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_07_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_2026_07_request_id_idx;


--

-- ----- Object: routing_decision_log_2026_07_success_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_07_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_07_success_ts_idx;


--

-- ----- Object: routing_decision_log_2026_07_tenant_id_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_07_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_2026_07_tenant_id_ts_idx;


--

-- ----- Object: routing_decision_log_2026_07_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_2026_07_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_2026_07_ts_idx;


--

-- ----- Object: routing_decision_log_default_chosen_credential_id_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_default_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_default_chosen_credential_id_ts_idx;


--

-- ----- Object: routing_decision_log_default_model_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_default_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_model ATTACH PARTITION public.routing_decision_log_default_model_ts_idx;


--

-- ----- Object: routing_decision_log_default_request_id_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_default_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_default_request_id_idx;


--

-- ----- Object: routing_decision_log_default_success_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_default_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_default_success_ts_idx;


--

-- ----- Object: routing_decision_log_default_tenant_id_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_default_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_tenant_ts ATTACH PARTITION public.routing_decision_log_default_tenant_id_ts_idx;


--

-- ----- Object: routing_decision_log_default_ts_idx (INDEX ATTACH) -----
-- Name: routing_decision_log_default_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_ts ATTACH PARTITION public.routing_decision_log_default_ts_idx;


--

-- ========================================
-- ROW SECURITY: 1 new objects
-- ========================================

-- ----- Object: routing_decision_log_archive (ROW SECURITY) -----
-- Name: routing_decision_log_archive; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.routing_decision_log_archive ENABLE ROW LEVEL SECURITY;

--

-- ========================================
-- POLICY: 1 new objects
-- ========================================

-- ----- Object: routing_decision_log_archive tenant_isolation_routing_decision_log_archive (POLICY) -----
-- Name: routing_decision_log_archive tenant_isolation_routing_decision_log_archive; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY tenant_isolation_routing_decision_log_archive ON public.routing_decision_log_archive USING ((tenant_id = public.get_current_tenant()));


--

-- ========================================
-- FUNCTION: 6 new objects
-- ========================================

-- ----- Object: archive_credential_model_index(date) (FUNCTION) -----
-- Name: archive_credential_model_index(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_credential_model_index(archive_month date) RETURNS TABLE(status text, rows_archived bigint, rows_deleted bigint)
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    month_start date := date_trunc('month', archive_month)::date;
		    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
		    partition_name text := 'credential_model_index_archive_' || to_char(month_start, 'YYYY_MM');
		    archived_count bigint;
		    deleted_count bigint;
		    cutoff_ts timestamptz := NOW() - INTERVAL '7 days';
		BEGIN
		    -- Create target columnar partition if missing
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF credential_model_index_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            partition_name, month_start, month_end
		        );
		    END IF;

		    -- Archive 7d+ data for this month to columnar
		    INSERT INTO credential_model_index_archive
		    SELECT * FROM credential_model_index
		    WHERE bucket >= month_start 
		      AND bucket < month_end
		      AND bucket < cutoff_ts
		    ON CONFLICT DO NOTHING;
		    
		    GET DIAGNOSTICS archived_count = ROW_COUNT;

		    -- Delete archived data from main table
		    DELETE FROM credential_model_index
		    WHERE bucket >= month_start 
		      AND bucket < month_end
		      AND bucket < cutoff_ts;
		    
		    GET DIAGNOSTICS deleted_count = ROW_COUNT;

		    RETURN QUERY SELECT 'success'::text, archived_count, deleted_count;
		END;
		$$;


--

-- ----- Object: archive_routing_decision_log(date) (FUNCTION) -----
-- Name: archive_routing_decision_log(date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.archive_routing_decision_log(archive_month date) RETURNS TABLE(status text, rows_migrated bigint, partition_dropped boolean)
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    month_start date := date_trunc('month', archive_month)::date;
		    month_end   date := (date_trunc('month', archive_month) + interval '1 month')::date;
		    src_part    text := 'routing_decision_log_' || to_char(month_start, 'YYYY_MM');
		    dst_part    text := 'routing_decision_log_archive_' || to_char(month_start, 'YYYY_MM');
		    row_count   bigint;
		    col_list    text;
		BEGIN
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = src_part AND relnamespace = 'public'::regnamespace) THEN
		        RETURN QUERY SELECT 'skipped'::text, 0::bigint, false;
		        RETURN;
		    END IF;

		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = dst_part AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF routing_decision_log_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            dst_part, month_start, month_end
		        );
		    END IF;

		    SELECT string_agg(a.column_name, ', ' ORDER BY a.ordinal_position)
		    INTO col_list
		    FROM information_schema.columns a
		    JOIN information_schema.columns r
		      ON a.table_schema = r.table_schema
		     AND a.column_name  = r.column_name
		    WHERE a.table_name = 'routing_decision_log_archive'
		      AND r.table_name = src_part
		      AND a.table_schema = 'public'
		      AND a.ordinal_position > 0;

		    IF col_list IS NULL OR length(col_list) = 0 THEN
		        RAISE EXCEPTION 'No common columns between % and routing_decision_log_archive', src_part;
		    END IF;

		    EXECUTE format(
		        'INSERT INTO %I (%s) SELECT %s FROM %I',
		        dst_part, col_list, col_list, src_part
		    );
		    GET DIAGNOSTICS row_count = ROW_COUNT;

		    EXECUTE format('ALTER TABLE routing_decision_log DETACH PARTITION %I', src_part);
		    EXECUTE format('DROP TABLE %I', src_part);

		    RETURN QUERY SELECT 'success'::text, row_count, true;
		END;
		$$;


--

-- ----- Object: cleanup_old_credential_model_index() (FUNCTION) -----
-- Name: cleanup_old_credential_model_index(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cleanup_old_credential_model_index() RETURNS bigint
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    deleted_count bigint;
		    cutoff_ts timestamptz := NOW() - INTERVAL '7 days';
		BEGIN
		    DELETE FROM credential_model_index
		    WHERE bucket < cutoff_ts;
		    
		    GET DIAGNOSTICS deleted_count = ROW_COUNT;
		    
		    RETURN deleted_count;
		END;
		$$;


--

-- ----- Object: create_next_month_routing_partitions() (FUNCTION) -----
-- Name: create_next_month_routing_partitions(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.create_next_month_routing_partitions() RETURNS void
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
		    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
		    month_suffix     text := to_char(next_month_start, 'YYYY_MM');
		    partition_name   text := 'routing_decision_log_' || month_suffix;
		BEGIN
		    -- Create main table heap partition
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF routing_decision_log FOR VALUES FROM (%L) TO (%L) USING heap',
		            partition_name, next_month_start, next_month_end
		        );
		    END IF;
		    
		    -- Create archive table columnar partition
		    PERFORM ensure_next_month_routing_archive_partition();
		END;
		$$;


--

-- ----- Object: ensure_next_month_cmi_archive_partition() (FUNCTION) -----
-- Name: ensure_next_month_cmi_archive_partition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_next_month_cmi_archive_partition() RETURNS void
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
		    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
		    partition_name   text := 'credential_model_index_archive_' || to_char(next_month_start, 'YYYY_MM');
		BEGIN
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF credential_model_index_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            partition_name, next_month_start, next_month_end
		        );
		    END IF;
		END;
		$$;


--

-- ----- Object: ensure_next_month_routing_archive_partition() (FUNCTION) -----
-- Name: ensure_next_month_routing_archive_partition(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.ensure_next_month_routing_archive_partition() RETURNS void
    LANGUAGE plpgsql
    AS $$
		DECLARE
		    next_month_start date := date_trunc('month', now() + interval '1 month')::date;
		    next_month_end   date := date_trunc('month', now() + interval '2 months')::date;
		    partition_name   text := 'routing_decision_log_archive_' || to_char(next_month_start, 'YYYY_MM');
		BEGIN
		    IF NOT EXISTS (SELECT 1 FROM pg_class
		                   WHERE relname = partition_name AND relnamespace = 'public'::regnamespace) THEN
		        EXECUTE format(
		            'CREATE TABLE %I PARTITION OF routing_decision_log_archive FOR VALUES FROM (%L) TO (%L) USING columnar',
		            partition_name, next_month_start, next_month_end
		        );
		    END IF;
		END;
		$$;


--

COMMIT;
