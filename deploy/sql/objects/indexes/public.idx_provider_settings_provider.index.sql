-- ===========================================================================
-- Object:   idx_provider_settings_provider
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_provider_settings_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_provider_settings_provider ON public.provider_settings USING btree (provider_id) WHERE (enabled = true);


--
