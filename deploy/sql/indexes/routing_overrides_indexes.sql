-- ============================================
-- Indexes for table: routing_overrides
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_routing_overrides_expires ON public.routing_overrides USING btree (expires_at) WHERE (expires_at IS NOT NULL);
CREATE INDEX idx_routing_overrides_task_profile ON public.routing_overrides USING btree (task_type, profile);
CREATE UNIQUE INDEX idx_routing_overrides_unique ON public.routing_overrides USING btree (task_type, profile, COALESCE(model_chosen, ''::text), mode);
