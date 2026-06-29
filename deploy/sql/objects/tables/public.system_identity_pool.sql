-- ===========================================================================
-- Object:   system_identity_pool
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: system_identity_pool; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.system_identity_pool (
    id integer DEFAULT 1 NOT NULL,
    max_identities integer DEFAULT 10000 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by text,
    CONSTRAINT system_identity_pool_id_check CHECK ((id = 1))
);


--
