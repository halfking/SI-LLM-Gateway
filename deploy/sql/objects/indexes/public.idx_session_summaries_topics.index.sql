-- ===========================================================================
-- Object:   idx_session_summaries_topics
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_session_summaries_topics; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_session_summaries_topics ON public.session_summaries USING gin (key_topics);


--
