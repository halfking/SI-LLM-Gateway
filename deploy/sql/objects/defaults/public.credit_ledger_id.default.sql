-- ===========================================================================
-- Object:   credit_ledger id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.credit_ledger ALTER COLUMN id SET DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass);


--
