-- ===========================================================================
-- Object:   asset_relationships pk_asset_relationships
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: asset_relationships pk_asset_relationships; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.asset_relationships
    ADD CONSTRAINT pk_asset_relationships PRIMARY KEY (src_kind, src_ref_id, dst_kind, dst_ref_id, rel);


--
