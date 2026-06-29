-- ===========================================================================
-- Object:   prompt_injection_detections id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: prompt_injection_detections id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.prompt_injection_detections ALTER COLUMN id SET DEFAULT nextval('public.prompt_injection_detections_id_seq'::regclass);


--
