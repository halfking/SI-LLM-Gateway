-- ===========================================================================
-- Object:   idx_wtmr_work_type
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_wtmr_work_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_wtmr_work_type ON public.work_type_model_route USING btree (work_type_key);


--
