-- ===========================================================================
-- Object:   idx_tool_usage_stats_tool_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tool_usage_stats_tool_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_usage_stats_tool_tenant ON public.tool_usage_stats_old USING btree (tool_id, tenant_id, usage_date DESC);


--
