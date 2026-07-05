-- ============================================
-- Indexes for table: tenant_tool_policies
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_tenant_tool_policies_enabled ON public.tenant_tool_policies USING btree (enabled);
CREATE INDEX idx_tenant_tool_policies_tenant ON public.tenant_tool_policies USING btree (tenant_id) WHERE (enabled = true);
