-- ===========================================================================
-- Object:   usage_ledger_2026_06 usage_ledger_2026_06_request_id_ts_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: usage_ledger_2026_06 usage_ledger_2026_06_request_id_ts_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.usage_ledger_2026_06
    ADD CONSTRAINT usage_ledger_2026_06_request_id_ts_key UNIQUE (request_id, ts);


--
