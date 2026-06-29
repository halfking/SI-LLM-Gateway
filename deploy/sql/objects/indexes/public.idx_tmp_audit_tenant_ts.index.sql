-- ===========================================================================
-- Object:   idx_tmp_audit_tenant_ts
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tmp_audit_tenant_ts; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tmp_audit_tenant_ts ON public.tenant_model_policies_audit USING btree (tenant_id, ts DESC);


--
