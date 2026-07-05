-- ============================================
-- Indexes for table: routing_decision_log_default
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX routing_decision_log_default_chosen_credential_id_ts_idx ON public.routing_decision_log_default USING btree (chosen_credential_id, ts DESC) WHERE (chosen_credential_id IS NOT NULL);
CREATE INDEX routing_decision_log_default_model_ts_idx ON public.routing_decision_log_default USING btree (model, ts DESC);
CREATE INDEX routing_decision_log_default_request_id_idx ON public.routing_decision_log_default USING btree (request_id);
CREATE INDEX routing_decision_log_default_success_ts_idx ON public.routing_decision_log_default USING btree (success, ts DESC);
CREATE INDEX routing_decision_log_default_tenant_id_ts_idx ON public.routing_decision_log_default USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);
CREATE INDEX routing_decision_log_default_ts_idx ON public.routing_decision_log_default USING btree (ts DESC);
