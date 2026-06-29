-- ===========================================================================
-- Object:   token_audit_events_id_seq
-- Type:     SEQUENCE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: token_audit_events_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.token_audit_events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: token_audit_events_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.token_audit_events_id_seq OWNED BY public.token_audit_events.id;


SET default_table_access_method = columnar;

--
