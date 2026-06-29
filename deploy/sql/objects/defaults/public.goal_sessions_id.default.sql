-- ===========================================================================
-- Object:   goal_sessions id
-- Type:     DEFAULT
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: goal_sessions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.goal_sessions ALTER COLUMN id SET DEFAULT nextval('public.goal_sessions_id_seq'::regclass);


--
