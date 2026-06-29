-- ===========================================================================
-- Object:   idx_tenants_name
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tenants_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenants_name ON public.tenants USING btree (name);


--
