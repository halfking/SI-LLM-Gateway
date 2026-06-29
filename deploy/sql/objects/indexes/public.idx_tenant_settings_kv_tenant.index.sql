-- ===========================================================================
-- Object:   idx_tenant_settings_kv_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tenant_settings_kv_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_settings_kv_tenant ON public.tenant_settings_kv USING btree (tenant_id);


--
