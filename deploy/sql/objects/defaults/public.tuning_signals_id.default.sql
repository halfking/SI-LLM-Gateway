-- ===========================================================================
-- Object:   tuning_signals id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tuning_signals id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tuning_signals ALTER COLUMN id SET DEFAULT nextval('public.tuning_signals_id_seq'::regclass);


--
