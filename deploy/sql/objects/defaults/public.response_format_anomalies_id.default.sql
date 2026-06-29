-- ===========================================================================
-- Object:   response_format_anomalies id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: response_format_anomalies id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.response_format_anomalies ALTER COLUMN id SET DEFAULT nextval('public.response_format_anomalies_id_seq'::regclass);


--
