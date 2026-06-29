-- ===========================================================================
-- Object:   tool_usage_stats_2026_06_tool_id_usage_date_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats_2026_06_tool_id_usage_date_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_tool_stats_part_tool ATTACH PARTITION public.tool_usage_stats_2026_06_tool_id_usage_date_idx;


--
