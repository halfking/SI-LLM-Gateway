-- ===========================================================================
-- Object:   routing_decision_log_default_request_id_idx
-- Type:     INDEX ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_default_request_id_idx; Type: INDEX ATTACH; Schema: public; Owner: -
--

ALTER INDEX public.idx_routing_decision_log_part_request_id ATTACH PARTITION public.routing_decision_log_default_request_id_idx;


--
