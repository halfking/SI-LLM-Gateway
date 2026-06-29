-- ===========================================================================
-- Object:   armor_judgments id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: armor_judgments id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.armor_judgments ALTER COLUMN id SET DEFAULT nextval('public.armor_judgments_id_seq'::regclass);


--
