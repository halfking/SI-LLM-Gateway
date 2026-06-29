-- ===========================================================================
-- Object:   idx_tool_registry_category
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tool_registry_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_registry_category ON public.tool_registry USING btree (category) WHERE (enabled = true);


--
