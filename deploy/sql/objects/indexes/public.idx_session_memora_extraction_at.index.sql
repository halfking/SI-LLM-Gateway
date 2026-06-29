-- ===========================================================================
-- Object:   idx_session_memora_extraction_at
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_session_memora_extraction_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_memora_extraction_at ON public.session_memora_extraction_log USING btree (extracted_at DESC);


--
