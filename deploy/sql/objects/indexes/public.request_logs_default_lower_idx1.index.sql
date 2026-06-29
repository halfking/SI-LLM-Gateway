-- ===========================================================================
-- Object:   request_logs_default_lower_idx1
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_lower_idx1; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_lower_idx1 ON public.request_logs_default USING btree (lower(client_model));


--
