-- ===========================================================================
-- Object:   request_logs_default_tenant_id_ts_idx2
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_tenant_id_ts_idx2; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_tenant_id_ts_idx2 ON public.request_logs_default USING btree (tenant_id, ts DESC) WHERE ((credits_charged IS NOT NULL) AND (credits_charged > 0));


--
