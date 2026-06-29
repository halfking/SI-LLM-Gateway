-- ===========================================================================
-- Object:   idx_applications_tenant_code
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_applications_tenant_code; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_applications_tenant_code ON public.applications USING btree (tenant_id, code) WHERE (enabled = true);


--
