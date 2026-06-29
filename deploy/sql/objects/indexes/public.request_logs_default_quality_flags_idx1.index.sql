-- ===========================================================================
-- Object:   request_logs_default_quality_flags_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_quality_flags_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_quality_flags_idx1 ON public.request_logs_default USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
