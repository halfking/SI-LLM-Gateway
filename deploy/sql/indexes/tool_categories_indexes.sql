-- ============================================
-- Indexes for table: tool_categories
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tool_categories_order ON public.tool_categories USING btree (display_order) WHERE (enabled = true);
