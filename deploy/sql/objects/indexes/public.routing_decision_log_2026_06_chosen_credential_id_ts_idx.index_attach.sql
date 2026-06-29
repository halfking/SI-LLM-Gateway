-- ===========================================================================
-- Object:   routing_decision_log_2026_06_chosen_credential_id_ts_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_2026_06_chosen_credential_id_ts_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_credential ATTACH PARTITION public.routing_decision_log_2026_06_chosen_credential_id_ts_idx;


--
