-- ===========================================================================
-- Object:   request_logs_2026_06_tenant_id_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_06_tenant_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_06_tenant_id_ts_idx1 ON public.request_logs_2026_06 USING btree (tenant_id, ts DESC) WHERE ((outbound_msg_count IS NOT NULL) AND (outbound_msg_count > 0));


--
