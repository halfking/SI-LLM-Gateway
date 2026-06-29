-- ===========================================================================
-- Object:   idx_tenant_tool_policies_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tenant_tool_policies_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_tool_policies_tenant ON public.tenant_tool_policies USING btree (tenant_id) WHERE (enabled = true);


--
