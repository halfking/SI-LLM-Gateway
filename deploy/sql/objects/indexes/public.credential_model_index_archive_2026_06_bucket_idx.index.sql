-- ===========================================================================
-- Object:   credential_model_index_archive_2026_06_bucket_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_index_archive_2026_06_bucket_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX credential_model_index_archive_2026_06_bucket_idx ON public.credential_model_index_archive_2026_06 USING btree (bucket DESC);


--
