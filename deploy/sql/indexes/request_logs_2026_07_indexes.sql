-- ============================================
-- Indexes for table: request_logs_2026_07
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX request_logs_2026_07_client_model_idx ON public.request_logs_2026_07 USING btree (client_model);
CREATE INDEX request_logs_2026_07_client_model_idx1 ON public.request_logs_2026_07 USING btree (client_model text_pattern_ops);
CREATE INDEX request_logs_2026_07_client_model_idx2 ON public.request_logs_2026_07 USING hash (client_model);
CREATE INDEX request_logs_2026_07_client_request_id_ts_idx ON public.request_logs_2026_07 USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);
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
