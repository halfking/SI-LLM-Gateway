-- ===========================================================================
-- Object:   idx_agents_heartbeat
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_agents_heartbeat; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agents_heartbeat ON public.agents USING btree (last_heartbeat) WHERE (last_heartbeat IS NOT NULL);


--
