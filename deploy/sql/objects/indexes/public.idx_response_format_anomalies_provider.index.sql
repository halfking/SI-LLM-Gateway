-- ===========================================================================
-- Object:   idx_response_format_anomalies_provider
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_response_format_anomalies_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_response_format_anomalies_provider ON public.response_format_anomalies USING btree (provider_code, client_model) WHERE (provider_code IS NOT NULL);


--
