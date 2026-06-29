-- ===========================================================================
-- Object:   credit_ledger_2026_08
-- Type:     TABLE ATTACH
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger_2026_08; Type: TABLE ATTACH; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger ATTACH PARTITION public.credit_ledger_2026_08 FOR VALUES FROM ('2026-08-01 00:00:00+00') TO ('2026-09-01 00:00:00+00');


--
