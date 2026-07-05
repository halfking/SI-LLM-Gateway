-- ============================================
-- Indexes for table: tuning_proposals
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tuning_proposals_cat ON public.tuning_proposals USING btree (category, task_type) WHERE (status = 'pending'::text);
CREATE INDEX idx_tuning_proposals_created ON public.tuning_proposals USING btree (created_at) WHERE (status = 'pending'::text);
CREATE INDEX idx_tuning_proposals_status ON public.tuning_proposals USING btree (status, ts DESC);
