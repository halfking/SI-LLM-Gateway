-- ============================================
-- Indexes for table: credential_model_bindings
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX idx_cmb_credential_provider_model ON public.credential_model_bindings USING btree (credential_id, provider_model_id);
CREATE INDEX idx_cmb_pending_verification ON public.credential_model_bindings USING btree (credential_id) WHERE (pending_verification = true);
CREATE INDEX idx_cmb_unavailable_recover_at ON public.credential_model_bindings USING btree (unavailable_recover_at) WHERE (available = false);
