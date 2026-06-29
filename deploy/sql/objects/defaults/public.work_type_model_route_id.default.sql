-- ===========================================================================
-- Object:   work_type_model_route id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: work_type_model_route id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.work_type_model_route ALTER COLUMN id SET DEFAULT nextval('public.work_type_model_route_id_seq'::regclass);


--
