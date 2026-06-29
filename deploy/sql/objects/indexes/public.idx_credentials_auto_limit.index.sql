-- ===========================================================================
-- Object:   idx_credentials_auto_limit
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_credentials_auto_limit; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_credentials_auto_limit ON public.credentials USING btree (concurrency_limit_auto) WHERE (concurrency_limit_auto IS NOT NULL);


--
