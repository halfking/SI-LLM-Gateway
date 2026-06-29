-- ===========================================================================
-- Object:   idx_request_logs_client_model_lower
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_client_model_lower; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_model_lower ON ONLY public.request_logs USING btree (lower(client_model));


--
