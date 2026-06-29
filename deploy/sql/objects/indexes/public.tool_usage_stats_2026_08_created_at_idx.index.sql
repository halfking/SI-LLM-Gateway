-- ===========================================================================
-- Object:   tool_usage_stats_2026_08_created_at_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_08_created_at_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX tool_usage_stats_2026_08_created_at_idx ON public.tool_usage_stats_2026_08 USING btree (created_at);


--
