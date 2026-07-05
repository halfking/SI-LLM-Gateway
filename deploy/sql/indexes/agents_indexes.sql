-- ============================================
-- Indexes for table: agents
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_agents_capabilities ON public.agents USING gin (capabilities jsonb_path_ops);
CREATE INDEX idx_agents_heartbeat ON public.agents USING btree (last_heartbeat) WHERE (last_heartbeat IS NOT NULL);
CREATE INDEX idx_agents_kind ON public.agents USING btree (tenant_id, kind);
CREATE INDEX idx_agents_tenant ON public.agents USING btree (tenant_id);
