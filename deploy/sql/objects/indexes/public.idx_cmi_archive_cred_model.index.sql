-- ===========================================================================
-- Object:   idx_cmi_archive_cred_model
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_cmi_archive_cred_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_cred_model ON ONLY public.credential_model_index_archive USING btree (credential_id, raw_model, bucket DESC);


--
