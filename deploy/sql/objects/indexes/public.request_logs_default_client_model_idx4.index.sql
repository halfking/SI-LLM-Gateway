-- ===========================================================================
-- Object:   request_logs_default_client_model_idx4
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_logs_default_client_model_idx4; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX request_logs_default_client_model_idx4 ON public.request_logs_default USING btree (client_model);


--
