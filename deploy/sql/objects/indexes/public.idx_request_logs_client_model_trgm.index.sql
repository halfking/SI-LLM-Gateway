-- ===========================================================================
-- Object:   idx_request_logs_client_model_trgm
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_client_model_trgm; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model_trgm ON ONLY public.request_logs USING gin (client_model public.gin_trgm_ops);


--
