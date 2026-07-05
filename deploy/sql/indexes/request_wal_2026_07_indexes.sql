-- ============================================
-- Indexes for table: request_wal_2026_07
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX request_wal_2026_07_gw_session_id_created_at_idx ON public.request_wal_2026_07 USING btree (gw_session_id, created_at);
CREATE INDEX request_wal_2026_07_status_stage_idx ON public.request_wal_2026_07 USING btree (status, stage);
CREATE INDEX request_wal_2026_07_tenant_id_created_at_idx ON public.request_wal_2026_07 USING btree (tenant_id, created_at DESC);
