-- ===========================================================================
-- Object:   idx_session_audit_records_session
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_session_audit_records_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_audit_records_session ON public.session_audit_records USING btree (session_id, created_at DESC);


--
