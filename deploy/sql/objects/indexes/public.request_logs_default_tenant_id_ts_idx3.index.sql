-- ===========================================================================
-- Object:   request_logs_default_tenant_id_ts_idx3
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_tenant_id_ts_idx3; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tenant_id_ts_idx3 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
