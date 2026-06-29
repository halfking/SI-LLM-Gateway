-- ===========================================================================
-- Object:   idx_request_logs_client_model_hash
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_client_model_hash; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model_hash ON ONLY public.request_logs USING hash (client_model);


--
