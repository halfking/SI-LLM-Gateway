-- ============================================
-- Indexes for table: credential_model_index_default
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE UNIQUE INDEX credential_model_index_defaul_bucket_credential_id_raw_mode_idx ON public.credential_model_index_default USING btree (bucket, credential_id, raw_model);
