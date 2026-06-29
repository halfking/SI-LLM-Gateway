-- ===========================================================================
-- Object:   idx_request_logs_outbound_msg_count
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_outbound_msg_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_outbound_msg_count ON ONLY public.request_logs USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
