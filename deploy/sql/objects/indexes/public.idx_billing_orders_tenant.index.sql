-- ===========================================================================
-- Object:   idx_billing_orders_tenant
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_billing_orders_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_orders_tenant ON public.billing_orders USING btree (tenant_id, created_at DESC);


--
