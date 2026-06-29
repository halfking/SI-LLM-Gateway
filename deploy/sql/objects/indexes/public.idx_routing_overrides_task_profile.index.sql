-- ===========================================================================
-- Object:   idx_routing_overrides_task_profile
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_overrides_task_profile; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_routing_overrides_task_profile ON public.routing_overrides USING btree (task_type, profile);


--
