-- ===========================================================================
-- Object:   idx_assets_tags
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_assets_tags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_assets_tags ON public.assets USING gin (tags jsonb_path_ops);


--
