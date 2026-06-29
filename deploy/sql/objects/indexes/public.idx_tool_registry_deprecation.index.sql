-- ===========================================================================
-- Object:   idx_tool_registry_deprecation
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tool_registry_deprecation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_registry_deprecation ON public.tool_registry USING btree (deprecation_date) WHERE (deprecation_date IS NOT NULL);


--
