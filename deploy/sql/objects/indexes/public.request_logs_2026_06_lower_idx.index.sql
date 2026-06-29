-- ===========================================================================
-- Object:   request_logs_2026_06_lower_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_06_lower_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_lower_idx ON public.request_logs_2026_06 USING btree (lower(client_model));


--
