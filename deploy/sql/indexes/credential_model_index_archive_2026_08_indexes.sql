-- ============================================
-- Indexes for table: credential_model_index_archive_2026_08
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE INDEX credential_model_index_archiv_credential_id_raw_model_bucke_idx ON public.credential_model_index_archive_2026_08 USING btree (credential_id, raw_model, bucket DESC);
CREATE INDEX credential_model_index_archive_2026_08_bucket_idx ON public.credential_model_index_archive_2026_08 USING btree (bucket DESC);
CREATE INDEX credential_model_index_archive_2026_08_canonical_id_bucket_idx ON public.credential_model_index_archive_2026_08 USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);
