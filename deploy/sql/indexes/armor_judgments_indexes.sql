-- ============================================
-- Indexes for table: armor_judgments
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_armor_judgments_request ON public.armor_judgments USING btree (request_id);
CREATE INDEX idx_armor_judgments_stats ON public.armor_judgments USING btree (check_type, decision);
CREATE INDEX idx_armor_judgments_tenant_time ON public.armor_judgments USING btree (tenant_id, created_at DESC);
