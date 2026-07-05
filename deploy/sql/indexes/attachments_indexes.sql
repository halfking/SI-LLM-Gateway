-- ============================================
-- Indexes for table: attachments
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_attachments_hash ON public.attachments USING btree (content_hash, tenant_id);
CREATE INDEX idx_attachments_request ON public.attachments USING btree (request_id);
CREATE INDEX idx_attachments_tenant_created ON public.attachments USING btree (tenant_id, created_at DESC);
