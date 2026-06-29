-- ===========================================================================
-- Object:   settings_kv
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: settings_kv; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.settings_kv (
    key character varying(128) NOT NULL,
    value jsonb NOT NULL,
    value_type character varying(32) NOT NULL,
    scope character varying(16) DEFAULT 'platform'::character varying NOT NULL,
    category character varying(32) DEFAULT 'general'::character varying NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by character varying(64),
    prev_value jsonb,
    prev_updated_at timestamp with time zone
);


--
