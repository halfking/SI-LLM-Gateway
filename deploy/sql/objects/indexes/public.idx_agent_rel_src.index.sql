-- ===========================================================================
-- Object:   idx_agent_rel_src
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_agent_rel_src; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_agent_rel_src ON public.agent_relationships USING btree (src_agent_id);


--
