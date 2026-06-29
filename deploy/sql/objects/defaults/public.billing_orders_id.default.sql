-- ===========================================================================
-- Object:   billing_orders id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: billing_orders id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.billing_orders ALTER COLUMN id SET DEFAULT nextval('public.billing_orders_id_seq'::regclass);


--
