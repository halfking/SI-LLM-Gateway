-- ===========================================================================
-- Object:   tool_usage_stats_2026_08_usage_date_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_08_usage_date_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_08_usage_date_idx ON public.tool_usage_stats_2026_08 USING btree (usage_date);


--
