-- ============================================
-- Indexes for table: passive_probe_state
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_passive_probe_reviewing ON public.passive_probe_state USING btree (in_reviewing, reviewing_until) WHERE (in_reviewing = true);
