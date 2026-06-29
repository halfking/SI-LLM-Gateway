-- ===========================================================================
-- Object:   routing_decision_log_2026_06_success_ts_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_2026_06_success_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_success ATTACH PARTITION public.routing_decision_log_2026_06_success_ts_idx;


--
