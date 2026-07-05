-- ============================================
-- Indexes for table: sticky_sessions
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE UNIQUE INDEX idx_sticky_sessions_sticky_key_unique ON public.sticky_sessions USING btree (sticky_key);
