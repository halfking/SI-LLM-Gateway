-- ===========================================================================
-- Object:   idx_settings_audit_created
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_settings_audit_created; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_audit_created ON public.settings_audit USING btree (created_at);


--
