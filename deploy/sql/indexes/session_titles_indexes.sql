-- ============================================
-- Indexes for table: session_titles
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_session_titles_generated_at ON public.session_titles USING btree (generated_at DESC);
