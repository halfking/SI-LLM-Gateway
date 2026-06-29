-- ===========================================================================
-- Object:   idx_tool_categories_order
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tool_categories_order; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tool_categories_order ON public.tool_categories USING btree (display_order) WHERE (enabled = true);


--
