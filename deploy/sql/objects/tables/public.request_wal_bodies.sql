-- ===========================================================================
-- Object:   request_wal_bodies
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: request_wal_bodies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.request_wal_bodies (
    request_id character varying(64) NOT NULL,
    outbound_body text,
    compression_meta jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
