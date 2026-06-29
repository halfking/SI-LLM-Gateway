-- ===========================================================================
-- Object:   idx_agents_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_agents_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_tenant ON public.agents USING btree (tenant_id);


--
