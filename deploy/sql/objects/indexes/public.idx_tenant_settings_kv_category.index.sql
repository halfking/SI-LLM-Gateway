-- ===========================================================================
-- Object:   idx_tenant_settings_kv_category
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tenant_settings_kv_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_settings_kv_category ON public.tenant_settings_kv USING btree (category);


--
