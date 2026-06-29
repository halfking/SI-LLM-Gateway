-- ===========================================================================
-- Object:   idx_routing_overrides_audit_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_overrides_audit_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_audit_ts ON public.routing_overrides_audit USING btree (ts DESC);


--
