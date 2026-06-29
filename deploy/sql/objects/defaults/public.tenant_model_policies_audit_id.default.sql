-- ===========================================================================
-- Object:   tenant_model_policies_audit id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tenant_model_policies_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tenant_model_policies_audit ALTER COLUMN id SET DEFAULT nextval('public.tenant_model_policies_audit_id_seq'::regclass);


--
