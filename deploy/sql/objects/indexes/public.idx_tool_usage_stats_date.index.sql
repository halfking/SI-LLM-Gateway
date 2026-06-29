-- ===========================================================================
-- Object:   idx_tool_usage_stats_date
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tool_usage_stats_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_usage_stats_date ON public.tool_usage_stats_old USING btree (usage_date DESC);


--
