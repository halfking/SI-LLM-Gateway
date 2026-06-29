-- ===========================================================================
-- Object:   idx_work_type_config_category
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_work_type_config_category; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_work_type_config_category ON public.work_type_config USING btree (category, sort_order);


--
