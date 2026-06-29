-- ===========================================================================
-- Object:   local_models id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: local_models id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.local_models ALTER COLUMN id SET DEFAULT nextval('public.local_models_id_seq'::regclass);


--
