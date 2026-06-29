-- ===========================================================================
-- Object:   applications id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: applications id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.applications ALTER COLUMN id SET DEFAULT nextval('public.applications_id_seq'::regclass);


--
