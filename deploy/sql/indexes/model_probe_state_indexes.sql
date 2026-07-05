-- ============================================
-- Indexes for table: model_probe_state
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_model_probe_state_retry ON public.model_probe_state USING btree (state, next_retry_at) WHERE (state = 'recovering'::text);
CREATE INDEX idx_mps_due ON public.model_probe_state USING btree (next_retry_at) WHERE (state = ANY (ARRAY['unknown'::text, 'recovering'::text]));
CREATE INDEX idx_mps_priority_next_retry ON public.model_probe_state USING btree (probe_priority, next_retry_at) WHERE (state = ANY (ARRAY['suspicious'::text, 'failing'::text, 'recovering'::text]));
CREATE INDEX idx_mps_probing ON public.model_probe_state USING btree (probing_started_at) WHERE (state = 'probing'::text);
CREATE INDEX idx_mps_success_rate ON public.model_probe_state USING btree (success_rate_7d);
CREATE INDEX idx_mps_suspicious_expired ON public.model_probe_state USING btree (state_expires_at) WHERE ((state = ANY (ARRAY['available'::text, 'unavailable'::text])) AND (state_expires_at IS NOT NULL));
CREATE INDEX idx_mps_suspicious_pending ON public.model_probe_state USING btree (marked_suspicious_at, next_retry_at) WHERE (state = 'suspicious'::text);
