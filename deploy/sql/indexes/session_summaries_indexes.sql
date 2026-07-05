-- ============================================
-- Indexes for table: session_summaries
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_session_summaries_compliance ON public.session_summaries USING btree (tenant_id, compliance_status) WHERE ((compliance_status)::text <> 'compliant'::text);
CREATE INDEX idx_session_summaries_cost ON public.session_summaries USING btree (tenant_id, total_cost_usd DESC);
CREATE INDEX idx_session_summaries_intent ON public.session_summaries USING btree (tenant_id, user_intent) WHERE (user_intent IS NOT NULL);
CREATE INDEX idx_session_summaries_models ON public.session_summaries USING gin (models_used);
CREATE INDEX idx_session_summaries_quality ON public.session_summaries USING btree (quality_score DESC) WHERE (quality_score IS NOT NULL);
CREATE INDEX idx_session_summaries_tenant_time ON public.session_summaries USING btree (tenant_id, last_request_at DESC);
CREATE INDEX idx_session_summaries_topics ON public.session_summaries USING gin (key_topics);
