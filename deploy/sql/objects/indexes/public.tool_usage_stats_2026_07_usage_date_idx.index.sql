-- ===========================================================================
-- Object:   tool_usage_stats_2026_07_usage_date_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_07_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_07_usage_date_idx ON public.tool_usage_stats_2026_07 USING btree (usage_date);


--
