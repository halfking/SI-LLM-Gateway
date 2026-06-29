-- ===========================================================================
-- Object:   idx_wal_tenant_created
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_wal_tenant_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wal_tenant_created ON ONLY public.request_wal USING btree (tenant_id, created_at DESC);


--
