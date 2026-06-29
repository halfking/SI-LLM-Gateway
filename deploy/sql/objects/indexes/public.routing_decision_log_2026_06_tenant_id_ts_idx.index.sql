-- ===========================================================================
-- Object:   routing_decision_log_2026_06_tenant_id_ts_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_decision_log_2026_06_tenant_id_ts_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX routing_decision_log_2026_06_tenant_id_ts_idx ON public.routing_decision_log_2026_06 USING btree (tenant_id, ts DESC) WHERE (tenant_id IS NOT NULL);


--
