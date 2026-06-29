-- ===========================================================================
-- Object:   request_logs_default_tenant_id_gw_task_id_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_tenant_id_gw_task_id_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tenant_id_gw_task_id_ts_idx1 ON public.request_logs_default USING btree (tenant_id, gw_task_id, ts DESC) WHERE ((gw_task_id IS NOT NULL) AND (gw_task_id <> ''::text));


--
