-- ===========================================================================
-- Object:   idx_assets_tenant_kind
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_assets_tenant_kind; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assets_tenant_kind ON public.assets USING btree (tenant_id, kind);


--
