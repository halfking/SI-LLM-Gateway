-- ===========================================================================
-- Object:   tuning_proposals id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tuning_proposals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tuning_proposals ALTER COLUMN id SET DEFAULT nextval('public.tuning_proposals_id_seq'::regclass);


--
