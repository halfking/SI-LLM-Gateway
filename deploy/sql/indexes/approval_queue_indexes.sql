-- ============================================
-- Indexes for table: approval_queue
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_approval_queue_expires ON public.approval_queue USING btree (expires_at) WHERE (status = 'pending'::text);
CREATE INDEX idx_approval_queue_session ON public.approval_queue USING btree (session_id, created_at DESC);
CREATE INDEX idx_approval_queue_tenant_pending ON public.approval_queue USING btree (tenant_id, created_at DESC) WHERE (status = 'pending'::text);
