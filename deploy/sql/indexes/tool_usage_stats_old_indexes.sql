-- ============================================
-- Indexes for table: tool_usage_stats_old
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tool_usage_stats_date ON public.tool_usage_stats_old USING btree (usage_date DESC);
CREATE INDEX idx_tool_usage_stats_tenant_id ON public.tool_usage_stats_old USING btree (tenant_id);
CREATE INDEX idx_tool_usage_stats_tool_id ON public.tool_usage_stats_old USING btree (tool_id);
CREATE INDEX idx_tool_usage_stats_tool_tenant ON public.tool_usage_stats_old USING btree (tool_id, tenant_id, usage_date DESC);
