-- ===========================================================================
-- Object:   provider_models id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: provider_models id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.provider_models ALTER COLUMN id SET DEFAULT nextval('public.provider_models_id_seq'::regclass);


--
