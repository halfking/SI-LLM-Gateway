-- ===========================================================================
-- Object:   output_compliance_policies id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: output_compliance_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.output_compliance_policies ALTER COLUMN id SET DEFAULT nextval('public.output_compliance_policies_id_seq'::regclass);


--
