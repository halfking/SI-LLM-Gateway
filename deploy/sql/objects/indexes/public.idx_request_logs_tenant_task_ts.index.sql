-- ===========================================================================
-- Object:   idx_request_logs_tenant_task_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_tenant_task_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_tenant_task_ts ON ONLY public.request_logs USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
