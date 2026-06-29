-- ===========================================================================
-- Object:   idx_billing_orders_status
-- Type:     INDEX
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: idx_billing_orders_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_billing_orders_status ON public.billing_orders USING btree (status, created_at DESC);


--
