-- ===========================================================================
-- Object:   routing_decision_log_default
-- Type:     TABLE ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_decision_log ATTACH PARTITION public.routing_decision_log_default DEFAULT;


--
