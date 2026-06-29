-- ===========================================================================
-- Object:   credential_quotas id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_quotas id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_quotas ALTER COLUMN id SET DEFAULT nextval('public.credential_quotas_id_seq'::regclass);


--
