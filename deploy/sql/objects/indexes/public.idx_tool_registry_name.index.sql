-- ===========================================================================
-- Object:   idx_tool_registry_name
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tool_registry_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_registry_name ON public.tool_registry USING btree (tool_name) WHERE (enabled = true);


--
