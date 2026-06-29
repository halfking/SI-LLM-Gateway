-- ===========================================================================
-- Object:   credential_health_checks id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_health_checks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_health_checks ALTER COLUMN id SET DEFAULT nextval('public.credential_health_checks_id_seq'::regclass);


--
