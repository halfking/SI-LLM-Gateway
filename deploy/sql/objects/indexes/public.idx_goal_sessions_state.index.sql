-- ===========================================================================
-- Object:   idx_goal_sessions_state
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_goal_sessions_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_sessions_state ON public.goal_sessions USING btree (state, last_activity_at);


--
