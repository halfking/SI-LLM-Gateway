-- ============================================
-- Indexes for table: handoff_logs
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_handoff_logs_session ON public.handoff_logs USING btree (session_id, created_at DESC);
CREATE INDEX idx_handoff_logs_tenant ON public.handoff_logs USING btree (tenant_id, created_at DESC);
