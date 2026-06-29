-- ===========================================================================
-- Object:   request_logs_2026_07_quality_flags_idx
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_2026_07_quality_flags_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_2026_07_quality_flags_idx ON public.request_logs_2026_07 USING gin (quality_flags) WHERE (cardinality(quality_flags) > 0);


--
