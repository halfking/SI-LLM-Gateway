-- ============================================
-- Indexes for table: asset_relationships
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_asset_rel_dst ON public.asset_relationships USING btree (dst_kind, dst_ref_id);
CREATE INDEX idx_asset_rel_src ON public.asset_relationships USING btree (src_kind, src_ref_id);
