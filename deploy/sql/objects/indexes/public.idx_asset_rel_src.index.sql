-- ===========================================================================
-- Object:   idx_asset_rel_src
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_asset_rel_src; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_asset_rel_src ON public.asset_relationships USING btree (src_kind, src_ref_id);


--
