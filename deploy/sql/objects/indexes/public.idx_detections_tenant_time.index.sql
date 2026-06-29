-- ===========================================================================
-- Object:   idx_detections_tenant_time
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_detections_tenant_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_detections_tenant_time ON public.prompt_injection_detections USING btree (tenant_id, detected_at DESC);


--
