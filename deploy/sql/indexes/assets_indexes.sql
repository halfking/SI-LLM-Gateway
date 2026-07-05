-- ============================================
-- Indexes for table: assets
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_assets_tags ON public.assets USING gin (tags jsonb_path_ops);
CREATE INDEX idx_assets_tenant_kind ON public.assets USING btree (tenant_id, kind);
