-- ===========================================================================
-- Object:   credit_ledger_2026_06
-- Type:     TABLE ATTACH
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger_2026_06; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_06 FOR VALUES FROM ('2026-06-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');


--
