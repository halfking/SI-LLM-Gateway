-- ===========================================================================
-- Object:   idx_tenant_subscriptions_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_tenant_subscriptions_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_tenant_subscriptions_tenant ON public.tenant_subscriptions USING btree (tenant_id, status);


--
