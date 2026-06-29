-- ===========================================================================
-- Object:   idx_approval_queue_session
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_approval_queue_session; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_approval_queue_session ON public.approval_queue USING btree (session_id, created_at DESC);


--
