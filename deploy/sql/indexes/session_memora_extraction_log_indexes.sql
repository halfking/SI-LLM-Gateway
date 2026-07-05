-- ============================================
-- Indexes for table: session_memora_extraction_log
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_session_memora_extraction_at ON public.session_memora_extraction_log USING btree (extracted_at DESC);
