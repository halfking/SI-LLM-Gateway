-- ===========================================================================
-- Object:   tool_usage_stats id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tool_usage_stats id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_usage_stats ALTER COLUMN id SET DEFAULT nextval('public.tool_usage_stats_partitioned_id_seq'::regclass);


--
