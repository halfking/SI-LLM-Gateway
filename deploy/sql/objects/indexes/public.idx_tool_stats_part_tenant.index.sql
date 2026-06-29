-- ===========================================================================
-- Object:   idx_tool_stats_part_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tool_stats_part_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_stats_part_tenant ON ONLY public.tool_usage_stats USING btree (tenant_id, usage_date);


--
