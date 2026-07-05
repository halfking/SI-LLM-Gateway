-- ============================================
-- Indexes for table: tool_usage_stats_2026_08
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX tool_usage_stats_2026_08_created_at_idx ON public.tool_usage_stats_2026_08 USING btree (created_at);
CREATE INDEX tool_usage_stats_2026_08_tenant_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tenant_id, usage_date);
CREATE INDEX tool_usage_stats_2026_08_tool_id_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (tool_id, usage_date);
CREATE INDEX tool_usage_stats_2026_08_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (usage_date);
