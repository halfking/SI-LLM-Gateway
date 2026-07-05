-- ============================================
-- Indexes for table: output_compliance_audit
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_output_audit_issue ON public.output_compliance_audit USING btree (tenant_id, issue_type, severity DESC);
CREATE INDEX idx_output_audit_request ON public.output_compliance_audit USING btree (request_id);
CREATE INDEX idx_output_audit_session ON public.output_compliance_audit USING btree (session_key);
CREATE INDEX idx_output_audit_tenant_time ON public.output_compliance_audit USING btree (tenant_id, detected_at DESC);
