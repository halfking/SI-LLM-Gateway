-- ===========================================================================
-- Object:   idx_call_history_cred_time
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_call_history_cred_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_call_history_cred_time ON public.credential_model_call_history USING btree (credential_id, window_start DESC);


--
