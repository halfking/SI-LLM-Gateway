-- ===========================================================================
-- Object:   idx_provider_settings_key
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_provider_settings_key; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_settings_key ON public.provider_settings USING btree (setting_key) WHERE (enabled = true);


--
