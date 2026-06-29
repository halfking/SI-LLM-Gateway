-- ===========================================================================
-- Object:   request_logs_2026_08_client_model_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_08_client_model_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_model_idx1 ON public.request_logs_2026_08 USING btree (client_model text_pattern_ops);


--
