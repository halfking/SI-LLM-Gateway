-- ===========================================================================
-- Object:   idx_detections_request
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_detections_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_detections_request ON public.prompt_injection_detections USING btree (request_id);


--
