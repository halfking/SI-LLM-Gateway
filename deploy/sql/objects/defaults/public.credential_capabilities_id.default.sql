-- ===========================================================================
-- Object:   credential_capabilities id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_capabilities id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_capabilities ALTER COLUMN id SET DEFAULT nextval('public.credential_capabilities_id_seq'::regclass);


--
