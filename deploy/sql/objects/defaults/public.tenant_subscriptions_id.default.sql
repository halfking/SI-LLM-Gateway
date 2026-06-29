-- ===========================================================================
-- Object:   tenant_subscriptions id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_subscriptions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_subscriptions ALTER COLUMN id SET DEFAULT nextval('public.tenant_subscriptions_id_seq'::regclass);


--
