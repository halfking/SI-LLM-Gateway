-- ===========================================================================
-- Object:   idx_handoff_logs_session
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_handoff_logs_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_handoff_logs_session ON public.handoff_logs USING btree (session_id, created_at DESC);


--
