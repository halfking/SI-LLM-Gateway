-- ===========================================================================
-- Object:   idx_routing_overrides_audit_override_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_overrides_audit_override_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_audit_override_ts ON public.routing_overrides_audit USING btree (override_id, ts DESC) WHERE (override_id IS NOT NULL);


--
