-- ===========================================================================
-- Object:   route_decisions id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: route_decisions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.route_decisions ALTER COLUMN id SET DEFAULT nextval('public.route_decisions_id_seq'::regclass);


--
