-- ===========================================================================
-- Object:   session_titles
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: session_titles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.session_titles (
    task_id text NOT NULL,
    scoped_session_id text DEFAULT ''::text NOT NULL,
    title text NOT NULL,
    generated_at timestamp with time zone DEFAULT now() NOT NULL,
    model text,
    api_key_id integer
);


--
