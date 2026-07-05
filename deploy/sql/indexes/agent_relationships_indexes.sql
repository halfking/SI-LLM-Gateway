-- ============================================
-- Indexes for table: agent_relationships
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_agent_rel_dst ON public.agent_relationships USING btree (dst_agent_id);
CREATE INDEX idx_agent_rel_src ON public.agent_relationships USING btree (src_agent_id);
