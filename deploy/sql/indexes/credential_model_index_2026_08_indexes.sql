-- ============================================
-- Indexes for table: credential_model_index_2026_08
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE UNIQUE INDEX credential_model_index_2026_0_bucket_credential_id_raw_mod_idx1 ON public.credential_model_index_2026_08 USING btree (bucket, credential_id, raw_model);
