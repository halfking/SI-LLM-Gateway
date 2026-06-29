-- ===========================================================================
-- Object:   request_logs_default_provider_id_quality_score_ts_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_provider_id_quality_score_ts_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_provider_id_quality_score_ts_idx1 ON public.request_logs_default USING btree (provider_id, quality_score, ts DESC) WHERE (quality_score IS NOT NULL);


--
