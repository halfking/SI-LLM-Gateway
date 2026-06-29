-- ===========================================================================
-- Object:   request_logs_default
-- Type:     TABLE ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.request_logs ATTACH PARTITION public.request_logs_default DEFAULT;


--
