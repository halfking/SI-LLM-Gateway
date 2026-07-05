-- ============================================
-- Indexes for table: analysis_events
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_analysis_events_session ON public.analysis_events USING btree (session_id, occurred_at DESC) WHERE (session_id IS NOT NULL);
CREATE INDEX idx_analysis_events_tenant_type ON public.analysis_events USING btree (tenant_id, type, occurred_at DESC);
CREATE INDEX idx_analysis_events_unprocessed ON public.analysis_events USING btree (occurred_at) WHERE (processed_at IS NULL);
