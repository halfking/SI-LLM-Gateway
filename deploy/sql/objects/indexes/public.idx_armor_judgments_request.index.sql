-- ===========================================================================
-- Object:   idx_armor_judgments_request
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_armor_judgments_request; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_armor_judgments_request ON public.armor_judgments USING btree (request_id);


--
