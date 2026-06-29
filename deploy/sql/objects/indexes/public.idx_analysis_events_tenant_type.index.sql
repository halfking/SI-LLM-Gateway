-- ===========================================================================
-- Object:   idx_analysis_events_tenant_type
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_analysis_events_tenant_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_analysis_events_tenant_type ON public.analysis_events USING btree (tenant_id, type, occurred_at DESC);


--
