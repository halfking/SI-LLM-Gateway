-- ===========================================================================
-- Object:   model_discovery_runs id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_discovery_runs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_discovery_runs ALTER COLUMN id SET DEFAULT nextval('public.model_discovery_runs_id_seq'::regclass);


--
