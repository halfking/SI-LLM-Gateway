-- ===========================================================================
-- Object:   idx_request_logs_quality_flags
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_request_logs_quality_flags; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_request_logs_quality_flags ON ONLY public.request_logs USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
