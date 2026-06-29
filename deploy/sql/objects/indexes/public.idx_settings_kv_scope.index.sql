-- ===========================================================================
-- Object:   idx_settings_kv_scope
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_settings_kv_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_kv_scope ON public.settings_kv USING btree (scope);


--
