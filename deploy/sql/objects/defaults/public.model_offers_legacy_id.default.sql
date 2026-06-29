-- ===========================================================================
-- Object:   model_offers_legacy id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: model_offers_legacy id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.model_offers_legacy ALTER COLUMN id SET DEFAULT nextval('public.model_offers_id_seq'::regclass);


--
