-- ===========================================================================
-- Object:   idx_session_summaries_intent
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_session_summaries_intent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_intent ON public.session_summaries USING btree (tenant_id, user_intent) WHERE (user_intent IS NOT NULL);


--
