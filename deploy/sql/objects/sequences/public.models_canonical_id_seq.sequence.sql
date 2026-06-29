-- ===========================================================================
-- Object:   models_canonical_id_seq
-- Type:     SEQUENCE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: models_canonical_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.models_canonical_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: models_canonical_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.models_canonical_id_seq OWNED BY public.models_canonical.id;


--
