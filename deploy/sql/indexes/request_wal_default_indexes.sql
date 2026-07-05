-- ============================================
-- Indexes for table: request_wal_default
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX request_wal_default_gw_session_id_created_at_idx ON public.request_wal_default USING btree (gw_session_id, created_at);
CREATE INDEX request_wal_default_status_stage_idx ON public.request_wal_default USING btree (status, stage);
CREATE INDEX request_wal_default_tenant_id_created_at_idx ON public.request_wal_default USING btree (tenant_id, created_at DESC);
