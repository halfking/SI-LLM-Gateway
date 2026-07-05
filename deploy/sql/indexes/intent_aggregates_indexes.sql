-- ============================================
-- Indexes for table: intent_aggregates
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_intent_aggregates_tenant_updated ON public.intent_aggregates USING btree (tenant_id, last_updated DESC);
