-- ===========================================================================
-- Object:   idx_cmi_archive_canonical
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_cmi_archive_canonical; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_cmi_archive_canonical ON ONLY public.credential_model_index_archive USING btree (canonical_id, bucket DESC) WHERE (canonical_id IS NOT NULL);


--
