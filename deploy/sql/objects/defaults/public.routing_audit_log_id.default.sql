-- ===========================================================================
-- Object:   routing_audit_log id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_audit_log id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_audit_log ALTER COLUMN id SET DEFAULT nextval('public.routing_audit_log_id_seq'::regclass);


--
