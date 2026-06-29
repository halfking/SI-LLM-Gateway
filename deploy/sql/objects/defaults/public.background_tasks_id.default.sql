-- ===========================================================================
-- Object:   background_tasks id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: background_tasks id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.background_tasks ALTER COLUMN id SET DEFAULT nextval('public.background_tasks_id_seq'::regclass);


--
