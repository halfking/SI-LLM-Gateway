-- ===========================================================================
-- Object:   idx_response_format_anomalies_detected_at
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_response_format_anomalies_detected_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_response_format_anomalies_detected_at ON public.response_format_anomalies USING btree (detected_at DESC);


--
