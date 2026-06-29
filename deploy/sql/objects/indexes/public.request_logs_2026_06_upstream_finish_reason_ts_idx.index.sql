-- ===========================================================================
-- Object:   request_logs_2026_06_upstream_finish_reason_ts_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_06_upstream_finish_reason_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_upstream_finish_reason_ts_idx ON public.request_logs_2026_06 USING btree (upstream_finish_reason, ts DESC) WHERE ((upstream_finish_reason IS NOT NULL) AND (upstream_finish_reason <> ''::text));


--
