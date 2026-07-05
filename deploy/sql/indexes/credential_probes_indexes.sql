-- ============================================
-- Indexes for table: credential_probes
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_credential_probes_cred_time ON public.credential_probes USING btree (credential_id, created_at DESC);
CREATE INDEX idx_credential_probes_success ON public.credential_probes USING btree (success, created_at DESC);
