-- ===========================================================================
-- Object:   request_logs_default_client_model_idx6
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_client_model_idx6; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_client_model_idx6 ON public.request_logs_default USING hash (client_model);


--
