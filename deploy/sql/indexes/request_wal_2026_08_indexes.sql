-- ============================================
-- Indexes for table: request_wal_2026_08
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX request_wal_2026_08_gw_session_id_created_at_idx ON public.request_wal_2026_08 USING btree (gw_session_id, created_at);
CREATE INDEX request_wal_2026_08_status_stage_idx ON public.request_wal_2026_08 USING btree (status, stage);
CREATE INDEX request_wal_2026_08_tenant_id_created_at_idx ON public.request_wal_2026_08 USING btree (tenant_id, created_at DESC);
