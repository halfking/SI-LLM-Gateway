-- ===========================================================================
-- Object:   prompt_injection_policies id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: prompt_injection_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_policies ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_policies_id_seq'::regclass);


--
