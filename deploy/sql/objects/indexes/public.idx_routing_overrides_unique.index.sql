-- ===========================================================================
-- Object:   idx_routing_overrides_unique
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_routing_overrides_unique; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_routing_overrides_unique ON public.routing_overrides USING btree (task_type, profile, COALESCE(model_chosen, ''::text), mode);


--
