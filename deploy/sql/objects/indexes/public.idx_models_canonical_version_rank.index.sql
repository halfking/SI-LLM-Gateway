-- ===========================================================================
-- Object:   idx_models_canonical_version_rank
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_models_canonical_version_rank; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_models_canonical_version_rank ON public.models_canonical USING btree (version_rank);


--
