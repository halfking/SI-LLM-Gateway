-- ===========================================================================
-- Object:   idx_usage_ledger_part_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_usage_ledger_part_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_usage_ledger_part_tenant ON ONLY public.usage_ledger USING btree (tenant_id, ts);


--
