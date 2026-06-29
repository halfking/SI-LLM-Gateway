-- ===========================================================================
-- Object:   idx_users_username
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_users_username; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_users_username ON public.users USING btree (username);


--
