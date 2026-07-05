-- ============================================
-- LLM Gateway Database Schema
-- Category: 01-request
-- Generated: 2026-07-05 17:14:34
-- ============================================

-- ----------------------------------------
-- Table: request_envelope
-- ----------------------------------------






-- Name: request_envelope; Type: TABLE; Schema: public; Owner: -

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



\unrestrict NyZBneNqSNR6hbrVPlcGk76dXdqEZSLSibI92z1VDzuddXboC36rOF6lk6D3djh


-- ----------------------------------------
-- Table: request_logs
-- ----------------------------------------





-- Name: request_logs; Type: TABLE; Schema: public; Owner: -

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


-- Name: COLUMN request_logs.cost_display; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.cost_display IS 'Request-level displayed cost in its native currency; may differ from cost_usd when provider pricing is not USD.';


-- Name: COLUMN request_logs.cost_currency; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.cost_currency IS 'Currency for request_logs.cost_display, e.g. USD/CNY.';


-- Name: COLUMN request_logs.is_auto_request; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.is_auto_request IS 'Auto route: was this request model=auto?';


-- Name: COLUMN request_logs.task_type; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.task_type IS 'Auto route: classified task type (chat/reasoning/code/...)';


-- Name: COLUMN request_logs.auto_profile; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.auto_profile IS 'Auto route: profile used (smart/speed_first/cost_first)';


-- Name: COLUMN request_logs.auto_decision; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.auto_decision IS 'Auto route: top-N candidates + chosen model + scoring breakdown';


-- Name: COLUMN request_logs.auto_confidence; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.auto_confidence IS 'Auto route: classification confidence 0-1';


-- Name: COLUMN request_logs.parent_request_id; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.parent_request_id IS 'Round 47 (2026-06-18): the pre-compression request_id when compressor rewrote the body. NULL for uncompressed rows. Single-level chain only (child has at most 1 parent).';


-- Name: COLUMN request_logs.compression_reason; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.compression_reason IS 'Round 47 (2026-06-18): why compression fired. mode_1_auto_threshold = body > cand.ContextWindow × 0.8 × 3.5 (LLM_GATEWAY_COMPRESSION_MODE=1). mode_2_on_4xx = upstream 4xx context_length_exceeded (LLM_GATEWAY_COMPRESSION_MODE=2). NULL = no compression event, OR pre-request trim happened without 4xx (T-NEW-4). See compression_meta.trim_phase for explicit phase tagging.';


-- Name: COLUMN request_logs.compression_strategy; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.compression_strategy IS 'Round 47 (2026-06-18): which decompression path succeeded. mechanical_trim = oldest-pair drop (transform/ctx_compress.go). memora_l1_inject = dynamic_context user message from Memora /product/search. llm_summary = 1M-context model summary. noop = attempted but skipped (e.g. warmup_min_facts guard).';


-- Name: COLUMN request_logs.compression_meta; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.compression_meta IS 'Round 47 (2026-06-18): compression telemetry. 4xx recovery fields (T-NEW-2): tokens_before/after, bytes_before/after, context_window_used, threshold_bytes, dropped_messages, summary_chars, model_used, latency_ms, memora_facts_used, warmup_skipped, first_user_retained, system_retained, reason_detail. Pre-request trim fields (T-NEW-4): trim_phase="pre_request", phases=["pre_request_trim"] or ["pre_request_trim","4xx_recovery"], reason_detail="pre-request trim (cand.ContextWindow × 0.85 × 3.5 threshold)". See v7 §3.2.';


-- Name: COLUMN request_logs.outbound_body; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.outbound_body IS 'v3 (2026-06-19): LLM wire body JSONB — what was actually forwarded to the
     upstream provider. NULL = no session compressor active (outbound == client).
     Differs from request_body when v3 session-level delta-append or proactive
     sliding-window summary rewrote the body before forwarding.';


-- Name: COLUMN request_logs.outbound_msg_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.outbound_msg_count IS 'v3 (2026-06-19): Message count inside outbound_body (including system).
     Compare to the client message count in request_body to measure delta.';


-- Name: COLUMN request_logs.outbound_token_est; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.outbound_token_est IS 'v3 (2026-06-19): Estimated token count for outbound_body using the
     3.5 chars/token heuristic (same as compressor/estimator.go). Used to
     audit sliding-window threshold decisions in request_logs UI.';


-- Name: COLUMN request_logs.outbound_msg_hashes; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.outbound_msg_hashes IS 'v3 (2026-06-19): Per-message fingerprint array [{index, sha256}] for
     outbound_body messages. The next request with the same gw_session_id
     reads this column to run LCS diff and find the incremental message tail,
     enabling delta-append without full re-send of conversation history.';


-- Name: COLUMN request_logs.upstream_finish_reason; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.upstream_finish_reason IS '2026-06-19 T-NEW-7: the SOLE home for the upstream finish_reason
     (stop, tool_calls, length, end_turn, function_call, max_tokens, …).
     NULL means the stream ended without a finish_reason (e.g. truncated
     pre-finish).  Populated for BOTH success and failure rows.
     This column REPLACES the prior use of failure_detail_code for
     finish reasons; see the migration header for the full rationale.';


-- Name: COLUMN request_logs.tool_calls; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.tool_calls IS 'Structured tool calls from assistant message. OpenAI format: [{id, type, function: {name, arguments}}]. Populated for both streaming and non-streaming responses.';


-- Name: COLUMN request_logs.upstream_status_code; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs.upstream_status_code IS 'HTTP status code returned by upstream (NULL = network-level error, success, or unknown). Populated from the last attempt in executor.go and persisted via telemetry/client.go INSERT/UPDATE.';


-- Name: idx_request_logs_client_model; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_client_model ON ONLY public.request_logs USING btree (client_model);


-- Name: idx_request_logs_client_model_hash; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_client_model_hash ON ONLY public.request_logs USING hash (client_model);


-- Name: idx_request_logs_client_model_lower; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_client_model_lower ON ONLY public.request_logs USING btree (lower(client_model));


-- Name: idx_request_logs_client_model_prefix; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_client_model_prefix ON ONLY public.request_logs USING btree (client_model text_pattern_ops);


-- Name: idx_request_logs_client_request_id; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_client_request_id ON ONLY public.request_logs USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


-- Name: idx_request_logs_credits_charged; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_credits_charged ON ONLY public.request_logs USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


-- Name: idx_request_logs_gw_session_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_gw_session_ts ON ONLY public.request_logs USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


-- Name: idx_request_logs_gw_task_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_gw_task_ts ON ONLY public.request_logs USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: idx_request_logs_has_attachments; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_has_attachments ON ONLY public.request_logs USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);


-- Name: idx_request_logs_outbound_msg_count; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_outbound_msg_count ON ONLY public.request_logs USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


-- Name: idx_request_logs_parent_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_parent_ts ON ONLY public.request_logs USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


-- Name: idx_request_logs_provider_model; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_provider_model ON ONLY public.request_logs USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);


-- Name: idx_request_logs_provider_quality; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_provider_quality ON ONLY public.request_logs USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


-- Name: idx_request_logs_provider_tool_calls; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_provider_tool_calls ON ONLY public.request_logs USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


-- Name: idx_request_logs_quality_flags; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_quality_flags ON ONLY public.request_logs USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


-- Name: idx_request_logs_request_id_ts_unique; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX idx_request_logs_request_id_ts_unique ON ONLY public.request_logs USING btree (request_id, ts);


-- Name: idx_request_logs_session_outbound; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_session_outbound ON ONLY public.request_logs USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


-- Name: idx_request_logs_status_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_status_ts ON ONLY public.request_logs USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


-- Name: idx_request_logs_tenant_task_ts; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_tenant_task_ts ON ONLY public.request_logs USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: idx_request_logs_tool_calls; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_tool_calls ON ONLY public.request_logs USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


-- Name: idx_request_logs_ts_desc; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_ts_desc ON ONLY public.request_logs USING btree (ts DESC);


-- Name: idx_request_logs_upstream_finish_reason; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_upstream_finish_reason ON ONLY public.request_logs USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


-- Name: idx_request_logs_upstream_status; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_upstream_status ON ONLY public.request_logs USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);


-- Name: idx_request_logs_work_type; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_request_logs_work_type ON ONLY public.request_logs USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


-- Name: request_logs trg_update_api_key_model_cost; Type: TRIGGER; Schema: public; Owner: -

CREATE TRIGGER trg_update_api_key_model_cost AFTER INSERT ON public.request_logs REFERENCING NEW TABLE AS new_rows FOR EACH STATEMENT EXECUTE FUNCTION public.update_api_key_model_cost_stmt();


-- Name: request_logs; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.request_logs ENABLE ROW LEVEL SECURITY;

-- Name: request_logs tenant_isolation_request_logs; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_request_logs ON public.request_logs USING ((tenant_id = public.get_current_tenant()));



\unrestrict ThsPJIa2S9CUlKWfnuNo4SoOgjJX48q1vMMCYEvCyQdaQB9cXxyLjI8GsgkJLnu


-- ----------------------------------------
-- Table: request_logs_2026_06
-- ----------------------------------------






-- Name: request_logs_2026_06; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_logs_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


-- Name: request_logs_2026_06_client_model_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_client_model_idx ON public.request_logs_2026_06 USING btree (client_model);


-- Name: request_logs_2026_06_client_model_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_client_model_idx1 ON public.request_logs_2026_06 USING btree (client_model text_pattern_ops);


-- Name: request_logs_2026_06_client_model_idx2; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_client_model_idx2 ON public.request_logs_2026_06 USING hash (client_model);


-- Name: request_logs_2026_06_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_client_request_id_ts_idx ON public.request_logs_2026_06 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


-- Name: request_logs_2026_06_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_gw_session_id_ts_idx ON public.request_logs_2026_06 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


-- Name: request_logs_2026_06_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_gw_session_id_ts_idx1 ON public.request_logs_2026_06 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


-- Name: request_logs_2026_06_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_gw_task_id_ts_idx ON public.request_logs_2026_06 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_06_has_attachments_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_has_attachments_ts_idx ON public.request_logs_2026_06 USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);


-- Name: request_logs_2026_06_lower_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_lower_idx ON public.request_logs_2026_06 USING btree (lower(client_model));


-- Name: request_logs_2026_06_parent_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_parent_request_id_ts_idx ON public.request_logs_2026_06 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


-- Name: request_logs_2026_06_provider_id_quality_score_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_provider_id_quality_score_ts_idx ON public.request_logs_2026_06 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


-- Name: request_logs_2026_06_provider_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_provider_id_ts_idx ON public.request_logs_2026_06 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


-- Name: request_logs_2026_06_provider_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_provider_model_ts_idx ON public.request_logs_2026_06 USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);


-- Name: request_logs_2026_06_quality_flags_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_quality_flags_idx ON public.request_logs_2026_06 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


-- Name: request_logs_2026_06_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX request_logs_2026_06_request_id_ts_idx ON public.request_logs_2026_06 USING btree (request_id, ts);


-- Name: request_logs_2026_06_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_request_status_ts_idx ON public.request_logs_2026_06 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


-- Name: request_logs_2026_06_tenant_id_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_06 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_06_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_tenant_id_ts_idx ON public.request_logs_2026_06 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


-- Name: request_logs_2026_06_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_tenant_id_ts_idx1 ON public.request_logs_2026_06 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


-- Name: request_logs_2026_06_tool_calls_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_tool_calls_idx ON public.request_logs_2026_06 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


-- Name: request_logs_2026_06_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_ts_idx ON public.request_logs_2026_06 USING btree (ts DESC);


-- Name: request_logs_2026_06_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_upstream_finish_reason_ts_idx ON public.request_logs_2026_06 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


-- Name: request_logs_2026_06_upstream_status_code_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_upstream_status_code_ts_idx ON public.request_logs_2026_06 USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);


-- Name: request_logs_2026_06_work_type_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_06_work_type_ts_idx ON public.request_logs_2026_06 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


-- Name: request_logs_2026_06_client_model_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_2026_06_client_model_idx;


-- Name: request_logs_2026_06_client_model_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_2026_06_client_model_idx1;


-- Name: request_logs_2026_06_client_model_idx2; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_2026_06_client_model_idx2;


-- Name: request_logs_2026_06_client_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_2026_06_client_request_id_ts_idx;


-- Name: request_logs_2026_06_gw_session_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_2026_06_gw_session_id_ts_idx;


-- Name: request_logs_2026_06_gw_session_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_2026_06_gw_session_id_ts_idx1;


-- Name: request_logs_2026_06_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_2026_06_gw_task_id_ts_idx;


-- Name: request_logs_2026_06_has_attachments_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_has_attachments ATTACH PARTITION public.request_logs_2026_06_has_attachments_ts_idx;


-- Name: request_logs_2026_06_lower_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_2026_06_lower_idx;


-- Name: request_logs_2026_06_parent_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_2026_06_parent_request_id_ts_idx;


-- Name: request_logs_2026_06_provider_id_quality_score_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_2026_06_provider_id_quality_score_ts_idx;


-- Name: request_logs_2026_06_provider_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_2026_06_provider_id_ts_idx;


-- Name: request_logs_2026_06_provider_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_provider_model ATTACH PARTITION public.request_logs_2026_06_provider_model_ts_idx;


-- Name: request_logs_2026_06_quality_flags_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_2026_06_quality_flags_idx;


-- Name: request_logs_2026_06_request_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_2026_06_request_id_ts_idx;


-- Name: request_logs_2026_06_request_status_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_2026_06_request_status_ts_idx;


-- Name: request_logs_2026_06_tenant_id_gw_task_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_2026_06_tenant_id_gw_task_id_ts_idx;


-- Name: request_logs_2026_06_tenant_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_2026_06_tenant_id_ts_idx;


-- Name: request_logs_2026_06_tenant_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_2026_06_tenant_id_ts_idx1;


-- Name: request_logs_2026_06_tool_calls_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_2026_06_tool_calls_idx;


-- Name: request_logs_2026_06_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_ts_desc ATTACH PARTITION public.request_logs_2026_06_ts_idx;


-- Name: request_logs_2026_06_upstream_finish_reason_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_2026_06_upstream_finish_reason_ts_idx;


-- Name: request_logs_2026_06_upstream_status_code_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_upstream_status ATTACH PARTITION public.request_logs_2026_06_upstream_status_code_ts_idx;


-- Name: request_logs_2026_06_work_type_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_2026_06_work_type_ts_idx;



\unrestrict B8MA0zocXJEBMBgghKCbqIOpZPjWczaIiOCWtWgMibEPmm4dY4bDN6t2Ef5gneP


-- ----------------------------------------
-- Table: request_logs_2026_07
-- ----------------------------------------






-- Name: request_logs_2026_07; Type: TABLE; Schema: public; Owner: -

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


-- Name: COLUMN request_logs_2026_07.cost_display; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.cost_display IS 'Request-level displayed cost in its native currency; may differ from cost_usd when provider pricing is not USD.';


-- Name: COLUMN request_logs_2026_07.cost_currency; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.cost_currency IS 'Currency for request_logs.cost_display, e.g. USD/CNY.';


-- Name: COLUMN request_logs_2026_07.is_auto_request; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.is_auto_request IS 'Auto route: was this request model=auto?';


-- Name: COLUMN request_logs_2026_07.task_type; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.task_type IS 'Auto route: classified task type (chat/reasoning/code/...)';


-- Name: COLUMN request_logs_2026_07.auto_profile; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.auto_profile IS 'Auto route: profile used (smart/speed_first/cost_first)';


-- Name: COLUMN request_logs_2026_07.auto_decision; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.auto_decision IS 'Auto route: top-N candidates + chosen model + scoring breakdown';


-- Name: COLUMN request_logs_2026_07.auto_confidence; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.auto_confidence IS 'Auto route: classification confidence 0-1';


-- Name: COLUMN request_logs_2026_07.parent_request_id; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.parent_request_id IS 'Round 47 (2026-06-18): the pre-compression request_id when compressor rewrote the body. NULL for uncompressed rows. Single-level chain only (child has at most 1 parent).';


-- Name: COLUMN request_logs_2026_07.compression_reason; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.compression_reason IS 'Round 47 (2026-06-18): why compression fired. mode_1_auto_threshold = body > cand.ContextWindow × 0.8 × 3.5 (LLM_GATEWAY_COMPRESSION_MODE=1). mode_2_on_4xx = upstream 4xx context_length_exceeded (LLM_GATEWAY_COMPRESSION_MODE=2). NULL = no compression event, OR pre-request trim happened without 4xx (T-NEW-4). See compression_meta.trim_phase for explicit phase tagging.';


-- Name: COLUMN request_logs_2026_07.compression_strategy; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.compression_strategy IS 'Round 47 (2026-06-18): which decompression path succeeded. mechanical_trim = oldest-pair drop (transform/ctx_compress.go). memora_l1_inject = dynamic_context user message from Memora /product/search. llm_summary = 1M-context model summary. noop = attempted but skipped (e.g. warmup_min_facts guard).';


-- Name: COLUMN request_logs_2026_07.compression_meta; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.compression_meta IS 'Round 47 (2026-06-18): compression telemetry. 4xx recovery fields (T-NEW-2): tokens_before/after, bytes_before/after, context_window_used, threshold_bytes, dropped_messages, summary_chars, model_used, latency_ms, memora_facts_used, warmup_skipped, first_user_retained, system_retained, reason_detail. Pre-request trim fields (T-NEW-4): trim_phase="pre_request", phases=["pre_request_trim"] or ["pre_request_trim","4xx_recovery"], reason_detail="pre-request trim (cand.ContextWindow × 0.85 × 3.5 threshold)". See v7 §3.2.';


-- Name: COLUMN request_logs_2026_07.outbound_body; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.outbound_body IS 'v3 (2026-06-19): LLM wire body JSONB — what was actually forwarded to the
     upstream provider. NULL = no session compressor active (outbound == client).
     Differs from request_body when v3 session-level delta-append or proactive
     sliding-window summary rewrote the body before forwarding.';


-- Name: COLUMN request_logs_2026_07.outbound_msg_count; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.outbound_msg_count IS 'v3 (2026-06-19): Message count inside outbound_body (including system).
     Compare to the client message count in request_body to measure delta.';


-- Name: COLUMN request_logs_2026_07.outbound_token_est; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.outbound_token_est IS 'v3 (2026-06-19): Estimated token count for outbound_body using the
     3.5 chars/token heuristic (same as compressor/estimator.go). Used to
     audit sliding-window threshold decisions in request_logs UI.';


-- Name: COLUMN request_logs_2026_07.outbound_msg_hashes; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.outbound_msg_hashes IS 'v3 (2026-06-19): Per-message fingerprint array [{index, sha256}] for
     outbound_body messages. The next request with the same gw_session_id
     reads this column to run LCS diff and find the incremental message tail,
     enabling delta-append without full re-send of conversation history.';


-- Name: COLUMN request_logs_2026_07.upstream_finish_reason; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.upstream_finish_reason IS '2026-06-19 T-NEW-7: the SOLE home for the upstream finish_reason
     (stop, tool_calls, length, end_turn, function_call, max_tokens, …).
     NULL means the stream ended without a finish_reason (e.g. truncated
     pre-finish).  Populated for BOTH success and failure rows.
     This column REPLACES the prior use of failure_detail_code for
     finish reasons; see the migration header for the full rationale.';


-- Name: COLUMN request_logs_2026_07.tool_calls; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.tool_calls IS 'Structured tool calls from assistant message. OpenAI format: [{id, type, function: {name, arguments}}]. Populated for both streaming and non-streaming responses.';


-- Name: COLUMN request_logs_2026_07.upstream_status_code; Type: COMMENT; Schema: public; Owner: -

COMMENT ON COLUMN public.request_logs_2026_07.upstream_status_code IS 'HTTP status code returned by upstream (NULL = network-level error, success, or unknown). Populated from the last attempt in executor.go and persisted via telemetry/client.go INSERT/UPDATE.';


-- Name: request_logs_2026_07_client_model_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_client_model_idx ON public.request_logs_2026_07 USING btree (client_model);


-- Name: request_logs_2026_07_client_model_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_client_model_idx1 ON public.request_logs_2026_07 USING btree (client_model text_pattern_ops);


-- Name: request_logs_2026_07_client_model_idx2; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_client_model_idx2 ON public.request_logs_2026_07 USING hash (client_model);


-- Name: request_logs_2026_07_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_client_request_id_ts_idx ON public.request_logs_2026_07 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


-- Name: request_logs_2026_07_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_gw_session_id_ts_idx ON public.request_logs_2026_07 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


-- Name: request_logs_2026_07_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_gw_session_id_ts_idx1 ON public.request_logs_2026_07 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


-- Name: request_logs_2026_07_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_gw_task_id_ts_idx ON public.request_logs_2026_07 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_07_has_attachments_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_has_attachments_ts_idx ON public.request_logs_2026_07 USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);


-- Name: request_logs_2026_07_lower_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_lower_idx ON public.request_logs_2026_07 USING btree (lower(client_model));


-- Name: request_logs_2026_07_parent_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_parent_request_id_ts_idx ON public.request_logs_2026_07 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


-- Name: request_logs_2026_07_provider_id_quality_score_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_provider_id_quality_score_ts_idx ON public.request_logs_2026_07 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


-- Name: request_logs_2026_07_provider_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_provider_id_ts_idx ON public.request_logs_2026_07 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


-- Name: request_logs_2026_07_provider_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_provider_model_ts_idx ON public.request_logs_2026_07 USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);


-- Name: request_logs_2026_07_quality_flags_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_quality_flags_idx ON public.request_logs_2026_07 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


-- Name: request_logs_2026_07_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX request_logs_2026_07_request_id_ts_idx ON public.request_logs_2026_07 USING btree (request_id, ts);


-- Name: request_logs_2026_07_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_request_status_ts_idx ON public.request_logs_2026_07 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


-- Name: request_logs_2026_07_tenant_id_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_07 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_07_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_tenant_id_ts_idx ON public.request_logs_2026_07 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


-- Name: request_logs_2026_07_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_tenant_id_ts_idx1 ON public.request_logs_2026_07 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


-- Name: request_logs_2026_07_tool_calls_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_tool_calls_idx ON public.request_logs_2026_07 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


-- Name: request_logs_2026_07_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_ts_idx ON public.request_logs_2026_07 USING btree (ts DESC);


-- Name: request_logs_2026_07_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_upstream_finish_reason_ts_idx ON public.request_logs_2026_07 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


-- Name: request_logs_2026_07_upstream_status_code_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_upstream_status_code_ts_idx ON public.request_logs_2026_07 USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);


-- Name: request_logs_2026_07_work_type_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_work_type_ts_idx ON public.request_logs_2026_07 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



\unrestrict HC361lbDfXNquVRU4zgucwqz6hcNUptLgKoSgbz6VZYgOaNgbZ6Uz0AsDx662Ns


-- ----------------------------------------
-- Table: request_logs_2026_07_columnar_backup
-- ----------------------------------------






-- Name: request_logs_2026_07_columnar_backup; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_logs_2026_07_col_client_model_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_client_model_idx ON public.request_logs_2026_07_columnar_backup USING btree (client_model);


-- Name: request_logs_2026_07_col_client_model_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_client_model_idx1 ON public.request_logs_2026_07_columnar_backup USING btree (client_model text_pattern_ops);


-- Name: request_logs_2026_07_col_client_model_idx2; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_client_model_idx2 ON public.request_logs_2026_07_columnar_backup USING hash (client_model);


-- Name: request_logs_2026_07_col_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_client_request_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


-- Name: request_logs_2026_07_col_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_gw_session_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


-- Name: request_logs_2026_07_col_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_gw_session_id_ts_idx1 ON public.request_logs_2026_07_columnar_backup USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


-- Name: request_logs_2026_07_col_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_gw_task_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_07_col_has_attachments_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_has_attachments_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);


-- Name: request_logs_2026_07_col_lower_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_lower_idx ON public.request_logs_2026_07_columnar_backup USING btree (lower(client_model));


-- Name: request_logs_2026_07_col_parent_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_parent_request_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


-- Name: request_logs_2026_07_col_provider_id_quality_score_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_provider_id_quality_score_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


-- Name: request_logs_2026_07_col_provider_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_provider_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


-- Name: request_logs_2026_07_col_provider_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_provider_model_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);


-- Name: request_logs_2026_07_col_quality_flags_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_quality_flags_idx ON public.request_logs_2026_07_columnar_backup USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


-- Name: request_logs_2026_07_col_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX request_logs_2026_07_col_request_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (request_id, ts);


-- Name: request_logs_2026_07_col_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_request_status_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


-- Name: request_logs_2026_07_col_tenant_id_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_07_col_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_tenant_id_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


-- Name: request_logs_2026_07_col_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_tenant_id_ts_idx1 ON public.request_logs_2026_07_columnar_backup USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


-- Name: request_logs_2026_07_col_tool_calls_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_tool_calls_idx ON public.request_logs_2026_07_columnar_backup USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


-- Name: request_logs_2026_07_col_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (ts DESC);


-- Name: request_logs_2026_07_col_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_upstream_finish_reason_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


-- Name: request_logs_2026_07_col_upstream_status_code_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_upstream_status_code_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);


-- Name: request_logs_2026_07_col_work_type_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_07_col_work_type_ts_idx ON public.request_logs_2026_07_columnar_backup USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



\unrestrict W9W6f9LEN5WPI1g5NkuBnNQhxdeKSxwp11BV6drALUuf0RbQeep76zdTlNX2dfY


-- ----------------------------------------
-- Table: request_logs_2026_08
-- ----------------------------------------






-- Name: request_logs_2026_08; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_logs_2026_08_heap_client_model_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_client_model_idx ON public.request_logs_2026_08 USING btree (client_model);


-- Name: request_logs_2026_08_heap_client_model_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_client_model_idx1 ON public.request_logs_2026_08 USING btree (client_model text_pattern_ops);


-- Name: request_logs_2026_08_heap_client_model_idx2; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_client_model_idx2 ON public.request_logs_2026_08 USING hash (client_model);


-- Name: request_logs_2026_08_heap_client_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_client_request_id_ts_idx ON public.request_logs_2026_08 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


-- Name: request_logs_2026_08_heap_gw_session_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_gw_session_id_ts_idx ON public.request_logs_2026_08 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


-- Name: request_logs_2026_08_heap_gw_session_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_gw_session_id_ts_idx1 ON public.request_logs_2026_08 USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


-- Name: request_logs_2026_08_heap_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_gw_task_id_ts_idx ON public.request_logs_2026_08 USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_08_heap_has_attachments_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_has_attachments_ts_idx ON public.request_logs_2026_08 USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);


-- Name: request_logs_2026_08_heap_lower_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_lower_idx ON public.request_logs_2026_08 USING btree (lower(client_model));


-- Name: request_logs_2026_08_heap_parent_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_parent_request_id_ts_idx ON public.request_logs_2026_08 USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


-- Name: request_logs_2026_08_heap_provider_id_quality_score_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_provider_id_quality_score_ts_idx ON public.request_logs_2026_08 USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


-- Name: request_logs_2026_08_heap_provider_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_provider_id_ts_idx ON public.request_logs_2026_08 USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


-- Name: request_logs_2026_08_heap_provider_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_provider_model_ts_idx ON public.request_logs_2026_08 USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);


-- Name: request_logs_2026_08_heap_quality_flags_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_quality_flags_idx ON public.request_logs_2026_08 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


-- Name: request_logs_2026_08_heap_request_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX request_logs_2026_08_heap_request_id_ts_idx ON public.request_logs_2026_08 USING btree (request_id, ts);


-- Name: request_logs_2026_08_heap_request_status_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_request_status_ts_idx ON public.request_logs_2026_08 USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


-- Name: request_logs_2026_08_heap_tenant_id_gw_task_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_tenant_id_gw_task_id_ts_idx ON public.request_logs_2026_08 USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_2026_08_heap_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_tenant_id_ts_idx ON public.request_logs_2026_08 USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


-- Name: request_logs_2026_08_heap_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_tenant_id_ts_idx1 ON public.request_logs_2026_08 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


-- Name: request_logs_2026_08_heap_tool_calls_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_tool_calls_idx ON public.request_logs_2026_08 USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


-- Name: request_logs_2026_08_heap_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_ts_idx ON public.request_logs_2026_08 USING btree (ts DESC);


-- Name: request_logs_2026_08_heap_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_upstream_finish_reason_ts_idx ON public.request_logs_2026_08 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


-- Name: request_logs_2026_08_heap_upstream_status_code_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_upstream_status_code_ts_idx ON public.request_logs_2026_08 USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);


-- Name: request_logs_2026_08_heap_work_type_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_2026_08_heap_work_type_ts_idx ON public.request_logs_2026_08 USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));



\unrestrict hOtocGIRJCSPtB387mL1IdyjrbmfjX1iKOZhzQ0NhjjWTDpXIVkHvWxJfCZb0mX


-- ----------------------------------------
-- Table: request_logs_archive
-- ----------------------------------------





-- Name: request_logs_archive; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_logs_archive; Type: ROW SECURITY; Schema: public; Owner: -

ALTER TABLE public.request_logs_archive ENABLE ROW LEVEL SECURITY;

-- Name: request_logs_archive tenant_isolation_request_logs_archive; Type: POLICY; Schema: public; Owner: -

CREATE POLICY tenant_isolation_request_logs_archive ON public.request_logs_archive USING ((tenant_id = public.get_current_tenant()));



\unrestrict rbbrU0fOHkX9GWSNRbfF0pCDC4oQfnDMYHHkpTAvRicvGzB9TIotc9GsprhOYI7


-- ----------------------------------------
-- Table: request_logs_archive_2026_08
-- ----------------------------------------






-- Name: request_logs_archive_2026_08; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_logs_archive_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.request_logs_archive ATTACH PARTITION public.request_logs_archive_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');



\unrestrict DyZOEs8KrCPtgAPGWJck2JnQOMU6qhHdeuJeGtVu5vF2O4Kk7qh8uQ5HhdZvLGU


-- ----------------------------------------
-- Table: request_logs_default
-- ----------------------------------------






-- Name: request_logs_default; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_logs_default; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_default DEFAULT;


-- Name: request_logs_default_client_model_idx4; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_client_model_idx4 ON public.request_logs_default USING btree (client_model);


-- Name: request_logs_default_client_model_idx5; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_client_model_idx5 ON public.request_logs_default USING btree (client_model text_pattern_ops);


-- Name: request_logs_default_client_model_idx6; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_client_model_idx6 ON public.request_logs_default USING hash (client_model);


-- Name: request_logs_default_client_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_client_request_id_ts_idx1 ON public.request_logs_default USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


-- Name: request_logs_default_gw_session_id_ts_idx2; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_gw_session_id_ts_idx2 ON public.request_logs_default USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (gw_session_id <> ''::text));


-- Name: request_logs_default_gw_session_id_ts_idx3; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_gw_session_id_ts_idx3 ON public.request_logs_default USING btree (gw_session_id, ts DESC) WHERE ((gw_session_id IS NOT NULL) AND (outbound_body IS NOT NULL));


-- Name: request_logs_default_gw_task_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_gw_task_id_ts_idx1 ON public.request_logs_default USING btree (gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_default_has_attachments_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_has_attachments_ts_idx ON public.request_logs_default USING btree (has_attachments, ts DESC) WHERE (has_attachments = true);


-- Name: request_logs_default_lower_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_lower_idx1 ON public.request_logs_default USING btree (lower(client_model));


-- Name: request_logs_default_parent_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_parent_request_id_ts_idx1 ON public.request_logs_default USING btree (parent_request_id, ts DESC) WHERE (parent_request_id IS NOT NULL);


-- Name: request_logs_default_provider_id_quality_score_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_provider_id_quality_score_ts_idx1 ON public.request_logs_default USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


-- Name: request_logs_default_provider_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_provider_id_ts_idx1 ON public.request_logs_default USING btree (provider_id, ts DESC) WHERE ((tool_calls IS NOT NULL) AND (jsonb_array_length(tool_calls) > 0));


-- Name: request_logs_default_provider_model_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_provider_model_ts_idx ON public.request_logs_default USING btree (provider_model, ts DESC) WHERE (provider_model IS NOT NULL);


-- Name: request_logs_default_quality_flags_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_quality_flags_idx1 ON public.request_logs_default USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


-- Name: request_logs_default_request_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE UNIQUE INDEX request_logs_default_request_id_ts_idx1 ON public.request_logs_default USING btree (request_id, ts);


-- Name: request_logs_default_request_status_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_request_status_ts_idx1 ON public.request_logs_default USING btree (request_status, ts DESC) WHERE ((request_status IS NOT NULL) AND (request_status <> ''::text));


-- Name: request_logs_default_tenant_id_gw_task_id_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_tenant_id_gw_task_id_ts_idx1 ON public.request_logs_default USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


-- Name: request_logs_default_tenant_id_ts_idx2; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_tenant_id_ts_idx2 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


-- Name: request_logs_default_tenant_id_ts_idx3; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_tenant_id_ts_idx3 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


-- Name: request_logs_default_tool_calls_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_tool_calls_idx1 ON public.request_logs_default USING gin (tool_calls) WHERE ((tool_calls IS NOT NULL) AND (tool_calls <> '[]'::jsonb));


-- Name: request_logs_default_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_ts_idx ON public.request_logs_default USING btree (ts DESC);


-- Name: request_logs_default_upstream_finish_reason_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_upstream_finish_reason_ts_idx1 ON public.request_logs_default USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


-- Name: request_logs_default_upstream_status_code_ts_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_upstream_status_code_ts_idx ON public.request_logs_default USING btree (upstream_status_code, ts DESC) WHERE (upstream_status_code IS NOT NULL);


-- Name: request_logs_default_work_type_ts_idx1; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_logs_default_work_type_ts_idx1 ON public.request_logs_default USING btree (work_type, ts DESC) WHERE ((work_type IS NOT NULL) AND (work_type <> ''::text));


-- Name: request_logs_default_client_model_idx4; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model ATTACH PARTITION public.request_logs_default_client_model_idx4;


-- Name: request_logs_default_client_model_idx5; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model_prefix ATTACH PARTITION public.request_logs_default_client_model_idx5;


-- Name: request_logs_default_client_model_idx6; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model_hash ATTACH PARTITION public.request_logs_default_client_model_idx6;


-- Name: request_logs_default_client_request_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_request_id ATTACH PARTITION public.request_logs_default_client_request_id_ts_idx1;


-- Name: request_logs_default_gw_session_id_ts_idx2; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_gw_session_ts ATTACH PARTITION public.request_logs_default_gw_session_id_ts_idx2;


-- Name: request_logs_default_gw_session_id_ts_idx3; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_session_outbound ATTACH PARTITION public.request_logs_default_gw_session_id_ts_idx3;


-- Name: request_logs_default_gw_task_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_gw_task_ts ATTACH PARTITION public.request_logs_default_gw_task_id_ts_idx1;


-- Name: request_logs_default_has_attachments_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_has_attachments ATTACH PARTITION public.request_logs_default_has_attachments_ts_idx;


-- Name: request_logs_default_lower_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_client_model_lower ATTACH PARTITION public.request_logs_default_lower_idx1;


-- Name: request_logs_default_parent_request_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_parent_ts ATTACH PARTITION public.request_logs_default_parent_request_id_ts_idx1;


-- Name: request_logs_default_provider_id_quality_score_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_provider_quality ATTACH PARTITION public.request_logs_default_provider_id_quality_score_ts_idx1;


-- Name: request_logs_default_provider_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_provider_tool_calls ATTACH PARTITION public.request_logs_default_provider_id_ts_idx1;


-- Name: request_logs_default_provider_model_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_provider_model ATTACH PARTITION public.request_logs_default_provider_model_ts_idx;


-- Name: request_logs_default_quality_flags_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_quality_flags ATTACH PARTITION public.request_logs_default_quality_flags_idx1;


-- Name: request_logs_default_request_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_request_id_ts_unique ATTACH PARTITION public.request_logs_default_request_id_ts_idx1;


-- Name: request_logs_default_request_status_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_status_ts ATTACH PARTITION public.request_logs_default_request_status_ts_idx1;


-- Name: request_logs_default_tenant_id_gw_task_id_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_tenant_task_ts ATTACH PARTITION public.request_logs_default_tenant_id_gw_task_id_ts_idx1;


-- Name: request_logs_default_tenant_id_ts_idx2; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_credits_charged ATTACH PARTITION public.request_logs_default_tenant_id_ts_idx2;


-- Name: request_logs_default_tenant_id_ts_idx3; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_outbound_msg_count ATTACH PARTITION public.request_logs_default_tenant_id_ts_idx3;


-- Name: request_logs_default_tool_calls_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_tool_calls ATTACH PARTITION public.request_logs_default_tool_calls_idx1;


-- Name: request_logs_default_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_ts_desc ATTACH PARTITION public.request_logs_default_ts_idx;


-- Name: request_logs_default_upstream_finish_reason_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_upstream_finish_reason ATTACH PARTITION public.request_logs_default_upstream_finish_reason_ts_idx1;


-- Name: request_logs_default_upstream_status_code_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_upstream_status ATTACH PARTITION public.request_logs_default_upstream_status_code_ts_idx;


-- Name: request_logs_default_work_type_ts_idx1; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_request_logs_work_type ATTACH PARTITION public.request_logs_default_work_type_ts_idx1;



\unrestrict UNTE0Xi0jkEDP39GnqEbG8gxpwZlBDqT7oHe0gamUhapu2Qe4Yren5VqnqWlBmZ


-- ----------------------------------------
-- Table: request_wal
-- ----------------------------------------





-- Name: request_wal; Type: TABLE; Schema: public; Owner: -

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


-- Name: TABLE request_wal; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.request_wal IS 'Request WAL: synchronous initial log + async batch updates for request lifecycle';


-- Name: request_wal request_wal_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal
    ADD CONSTRAINT request_wal_pkey PRIMARY KEY (request_id, created_at);


-- Name: idx_wal_session; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_wal_session ON ONLY public.request_wal USING btree (gw_session_id, created_at);


-- Name: idx_wal_status_stage; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_wal_status_stage ON ONLY public.request_wal USING btree (status, stage);


-- Name: idx_wal_tenant_created; Type: INDEX; Schema: public; Owner: -

CREATE INDEX idx_wal_tenant_created ON ONLY public.request_wal USING btree (tenant_id, created_at DESC);



\unrestrict pIDJfucLqILJgx52HOhWUOMS4JjOUikR0bzM12eZF5DTjCDFuOqErLS1ztVUOKb


-- ----------------------------------------
-- Table: request_wal_2026_06
-- ----------------------------------------






-- Name: request_wal_2026_06; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_wal_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


-- Name: request_wal_2026_06 request_wal_2026_06_col_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal_2026_06
    ADD CONSTRAINT request_wal_2026_06_col_pkey PRIMARY KEY (request_id, created_at);


-- Name: request_wal_2026_06_col_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_06_col_gw_session_id_created_at_idx ON public.request_wal_2026_06 USING btree (gw_session_id, created_at);


-- Name: request_wal_2026_06_col_status_stage_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_06_col_status_stage_idx ON public.request_wal_2026_06 USING btree (status, stage);


-- Name: request_wal_2026_06_col_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_06_col_tenant_id_created_at_idx ON public.request_wal_2026_06 USING btree (tenant_id, created_at DESC);


-- Name: request_wal_2026_06_col_gw_session_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_06_col_gw_session_id_created_at_idx;


-- Name: request_wal_2026_06_col_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_06_col_pkey;


-- Name: request_wal_2026_06_col_status_stage_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_06_col_status_stage_idx;


-- Name: request_wal_2026_06_col_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_06_col_tenant_id_created_at_idx;



\unrestrict vAkHvFfCGQXG5cqWwgHiGNgAg02Ms2U8dNeAcM0mjsxffUMR7f1ZvaiOrVEkGot


-- ----------------------------------------
-- Table: request_wal_2026_07
-- ----------------------------------------






-- Name: request_wal_2026_07; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_wal_2026_07; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_07 FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-08-01 00:00:00+00');


-- Name: request_wal_2026_07 request_wal_2026_07_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal_2026_07
    ADD CONSTRAINT request_wal_2026_07_pkey PRIMARY KEY (request_id, created_at);


-- Name: request_wal_2026_07_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_07_gw_session_id_created_at_idx ON public.request_wal_2026_07 USING btree (gw_session_id, created_at);


-- Name: request_wal_2026_07_status_stage_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_07_status_stage_idx ON public.request_wal_2026_07 USING btree (status, stage);


-- Name: request_wal_2026_07_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_07_tenant_id_created_at_idx ON public.request_wal_2026_07 USING btree (tenant_id, created_at DESC);


-- Name: request_wal_2026_07_gw_session_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_07_gw_session_id_created_at_idx;


-- Name: request_wal_2026_07_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_07_pkey;


-- Name: request_wal_2026_07_status_stage_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_07_status_stage_idx;


-- Name: request_wal_2026_07_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_07_tenant_id_created_at_idx;



\unrestrict YYVYr9DclUmaQtR2dAPnY3eqUsmVc1q92n7ZmT9qy5HO1V7PpmawTEe0dY25xRl


-- ----------------------------------------
-- Table: request_wal_2026_07_columnar
-- ----------------------------------------






-- Name: request_wal_2026_07_columnar; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_wal_2026_07_columnar request_wal_2026_07_col_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal_2026_07_columnar
    ADD CONSTRAINT request_wal_2026_07_col_pkey PRIMARY KEY (request_id, created_at);


-- Name: request_wal_2026_07_col_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_07_col_gw_session_id_created_at_idx ON public.request_wal_2026_07_columnar USING btree (gw_session_id, created_at);


-- Name: request_wal_2026_07_col_status_stage_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_07_col_status_stage_idx ON public.request_wal_2026_07_columnar USING btree (status, stage);


-- Name: request_wal_2026_07_col_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_07_col_tenant_id_created_at_idx ON public.request_wal_2026_07_columnar USING btree (tenant_id, created_at DESC);



\unrestrict ymtnUlmd1mpuR5W9xpeAlVyyyoh4HssAOb9qxDAwduukseQNQnOXqezf2m9f6tf


-- ----------------------------------------
-- Table: request_wal_2026_08
-- ----------------------------------------






-- Name: request_wal_2026_08; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_wal_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


-- Name: request_wal_2026_08 request_wal_2026_08_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal_2026_08
    ADD CONSTRAINT request_wal_2026_08_pkey PRIMARY KEY (request_id, created_at);


-- Name: request_wal_2026_08_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_08_gw_session_id_created_at_idx ON public.request_wal_2026_08 USING btree (gw_session_id, created_at);


-- Name: request_wal_2026_08_status_stage_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_08_status_stage_idx ON public.request_wal_2026_08 USING btree (status, stage);


-- Name: request_wal_2026_08_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_2026_08_tenant_id_created_at_idx ON public.request_wal_2026_08 USING btree (tenant_id, created_at DESC);


-- Name: request_wal_2026_08_gw_session_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_2026_08_gw_session_id_created_at_idx;


-- Name: request_wal_2026_08_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_2026_08_pkey;


-- Name: request_wal_2026_08_status_stage_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_2026_08_status_stage_idx;


-- Name: request_wal_2026_08_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_2026_08_tenant_id_created_at_idx;



\unrestrict 3xYhNDa8UYKBSoG1zcLON58CZwFB5evnSELGvHlTgzkD9WDlCUcU6so3V7gbsKa


-- ----------------------------------------
-- Table: request_wal_bodies
-- ----------------------------------------






-- Name: request_wal_bodies; Type: TABLE; Schema: public; Owner: -

CREATE TABLE public.request_wal_bodies (
    request_id character varying(64) NOT NULL,
    outbound_body text,
    compression_meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


-- Name: TABLE request_wal_bodies; Type: COMMENT; Schema: public; Owner: -

COMMENT ON TABLE public.request_wal_bodies IS 'Large outbound bodies separated for performance';



\unrestrict v0CZ7a7R3YzX6CbcTsDGvyQRHTgjUUQfeAFiRrka0XH2NzhDM61zOmJtBxxK248


-- ----------------------------------------
-- Table: request_wal_default
-- ----------------------------------------






-- Name: request_wal_default; Type: TABLE; Schema: public; Owner: -

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


-- Name: request_wal_default; Type: TABLE ATTACH; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal ATTACH PARTITION public.request_wal_default DEFAULT;


-- Name: request_wal_default request_wal_default_pkey; Type: CONSTRAINT; Schema: public; Owner: -

ALTER TABLE ONLY public.request_wal_default
    ADD CONSTRAINT request_wal_default_pkey PRIMARY KEY (request_id, created_at);


-- Name: request_wal_default_gw_session_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_default_gw_session_id_created_at_idx ON public.request_wal_default USING btree (gw_session_id, created_at);


-- Name: request_wal_default_status_stage_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_default_status_stage_idx ON public.request_wal_default USING btree (status, stage);


-- Name: request_wal_default_tenant_id_created_at_idx; Type: INDEX; Schema: public; Owner: -

CREATE INDEX request_wal_default_tenant_id_created_at_idx ON public.request_wal_default USING btree (tenant_id, created_at DESC);


-- Name: request_wal_default_gw_session_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_session ATTACH PARTITION public.request_wal_default_gw_session_id_created_at_idx;


-- Name: request_wal_default_pkey; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.request_wal_pkey ATTACH PARTITION public.request_wal_default_pkey;


-- Name: request_wal_default_status_stage_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_status_stage ATTACH PARTITION public.request_wal_default_status_stage_idx;


-- Name: request_wal_default_tenant_id_created_at_idx; Type: INDEX ATTACH; Schema: public; Owner: -

ALTER INDEX public.idx_wal_tenant_created ATTACH PARTITION public.request_wal_default_tenant_id_created_at_idx;



\unrestrict EnkZyFerodPBlbLM72dRlW8i2WP9pHJduG2CggelvTebW2hC7oPVswDjKksmVj9


