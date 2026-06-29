-- ===========================================================================
-- Object:   idx_session_summaries_compliance
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_session_summaries_compliance; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_compliance ON public.session_summaries USING btree (tenant_id, compliance_status) WHERE ((compliance_status)::text <> 'compliant'::text);


--
