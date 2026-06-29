-- ===========================================================================
-- Object:   idx_routing_overrides_audit_actor_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_overrides_audit_actor_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_audit_actor_ts ON public.routing_overrides_audit USING btree (actor, ts DESC) WHERE (actor IS NOT NULL);


--
