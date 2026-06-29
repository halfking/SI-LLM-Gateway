-- ===========================================================================
-- Object:   credential_quota_usage id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_quota_usage id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credential_quota_usage ALTER COLUMN id SET DEFAULT nextval('public.credential_quota_usage_id_seq'::regclass);


--
