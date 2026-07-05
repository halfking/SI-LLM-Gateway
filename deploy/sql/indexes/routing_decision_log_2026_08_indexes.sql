-- ============================================
-- Indexes for table: routing_decision_log_2026_08
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX routing_decision_log_2026_08_chosen_credential_id_ts_idx ON public.routing_decision_log_2026_08 USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);
CREATE INDEX routing_decision_log_2026_08_model_ts_idx ON public.routing_decision_log_2026_08 USING btree (model, ts DESC);
CREATE INDEX routing_decision_log_2026_08_request_id_idx ON public.routing_decision_log_2026_08 USING btree (request_id);
CREATE INDEX routing_decision_log_2026_08_success_ts_idx ON public.routing_decision_log_2026_08 USING btree (success, ts DESC);
CREATE INDEX routing_decision_log_2026_08_tenant_id_ts_idx ON public.routing_decision_log_2026_08 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);
CREATE INDEX routing_decision_log_2026_08_ts_idx ON public.routing_decision_log_2026_08 USING btree (ts DESC);
