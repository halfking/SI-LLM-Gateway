-- ===========================================================================
-- Object:   billing_orders billing_orders_order_no_key
-- Type:     CONSTRAINT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: billing_orders billing_orders_order_no_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_orders
    ADD CONSTRAINT billing_orders_order_no_key UNIQUE (order_no);


--
