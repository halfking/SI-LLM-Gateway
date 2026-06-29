-- ===========================================================================
-- Object:   usage_ledger_2026_06
-- Type:     TABLE ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: usage_ledger_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger ATTACH PARTITION public.usage_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
