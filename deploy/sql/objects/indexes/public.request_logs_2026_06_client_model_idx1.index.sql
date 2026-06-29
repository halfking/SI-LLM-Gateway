-- ===========================================================================
-- Object:   request_logs_2026_06_client_model_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_06_client_model_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_client_model_idx1 ON public.request_logs_2026_06 USING btree (client_model text_pattern_ops);


--
