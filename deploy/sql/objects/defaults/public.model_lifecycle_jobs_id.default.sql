-- ===========================================================================
-- Object:   model_lifecycle_jobs id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_lifecycle_jobs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_lifecycle_jobs ALTER COLUMN id SET DEFAULT nextval('public.model_lifecycle_jobs_id_seq'::regclass);


--
