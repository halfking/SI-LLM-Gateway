-- ===========================================================================
-- Object:   routing_decision_log_2026_06
-- Type:     TABLE ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
