-- ===========================================================================
-- Object:   routing_overrides_audit id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: routing_overrides_audit id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.routing_overrides_audit ALTER COLUMN id SET DEFAULT nextval('public.routing_overrides_audit_id_seq'::regclass);


--
