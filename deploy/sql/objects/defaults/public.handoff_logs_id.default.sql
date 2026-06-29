-- ===========================================================================
-- Object:   handoff_logs id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: handoff_logs id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.handoff_logs ALTER COLUMN id SET DEFAULT nextval('public.handoff_logs_id_seq'::regclass);


--
