-- ============================================
-- Indexes for table: tool_registry
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tool_registry_category ON public.tool_registry USING btree (category) WHERE (enabled = true);
CREATE INDEX idx_tool_registry_deprecation ON public.tool_registry USING btree (deprecation_date) WHERE (deprecation_date IS NOT NULL);
CREATE INDEX idx_tool_registry_name ON public.tool_registry USING btree (tool_name) WHERE (enabled = true);
CREATE INDEX idx_tool_registry_tenant_tool ON public.tool_registry USING btree (tenant_id, tool_id, version DESC);
CREATE UNIQUE INDEX idx_tool_registry_unique_version ON public.tool_registry USING btree (tenant_id, tool_id, version);
