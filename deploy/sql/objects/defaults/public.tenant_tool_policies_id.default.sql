-- ===========================================================================
-- Object:   tenant_tool_policies id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_tool_policies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_tool_policies ALTER COLUMN id SET DEFAULT nextval('public.tenant_tool_policies_id_seq'::regclass);


--
