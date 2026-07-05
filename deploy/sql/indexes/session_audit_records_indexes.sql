-- ============================================
-- Indexes for table: session_audit_records
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_session_audit_records_session ON public.session_audit_records USING btree (session_id, created_at DESC);
CREATE INDEX idx_session_audit_records_status ON public.session_audit_records USING btree (status, created_at DESC) WHERE (status = 'need_approval'::text);
CREATE INDEX idx_session_audit_records_tenant_created ON public.session_audit_records USING btree (tenant_id, created_at DESC);
