-- ===========================================================================
-- Object:   idx_settings_audit_operator
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_settings_audit_operator; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_settings_audit_operator ON public.settings_audit USING btree (operator_user, created_at DESC);


--
