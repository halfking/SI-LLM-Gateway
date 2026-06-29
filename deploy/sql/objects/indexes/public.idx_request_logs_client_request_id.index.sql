-- ===========================================================================
-- Object:   idx_request_logs_client_request_id
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_client_request_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_client_request_id ON ONLY public.request_logs USING btree (client_request_id, ts DESC) WHERE (client_request_id IS NOT NULL);


--
