-- ===========================================================================
-- Object:   session_audit_records id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: session_audit_records id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.session_audit_records ALTER COLUMN id SET DEFAULT nextval('public.session_audit_records_id_seq'::regclass);


--
