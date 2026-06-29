-- ===========================================================================
-- Object:   idx_goal_sessions_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_goal_sessions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_goal_sessions_tenant ON public.goal_sessions USING btree (tenant_id, state);


--
