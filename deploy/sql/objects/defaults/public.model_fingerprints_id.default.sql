-- ===========================================================================
-- Object:   model_fingerprints id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_fingerprints id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_fingerprints ALTER COLUMN id SET DEFAULT nextval('public.model_fingerprints_id_seq'::regclass);


--
