-- ===========================================================================
-- Object:   request_logs_2026_08_client_model_idx3
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_08_client_model_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_08_client_model_idx3 ON public.request_logs_2026_08 USING gin (client_model public.gin_trgm_ops);


--
