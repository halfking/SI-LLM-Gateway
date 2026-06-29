-- ===========================================================================
-- Object:   request_logs_2026_07_client_model_idx2
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_07_client_model_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_client_model_idx2 ON public.request_logs_2026_07 USING hash (client_model);


--
