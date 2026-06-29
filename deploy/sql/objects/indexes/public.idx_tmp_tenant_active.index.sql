-- ===========================================================================
-- Object:   idx_tmp_tenant_active
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tmp_tenant_active; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tmp_tenant_active ON public.tenant_model_policies USING btree (tenant_id) WHERE (deleted_at IS NULL);


--
