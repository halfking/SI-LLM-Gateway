-- ===========================================================================
-- Object:   provider_events
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: provider_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.provider_events (
    id bigint,
    credential_id bigint,
    event_kind text,
    payload_json jsonb,
    ts timestamp with time zone
);


SET default_table_access_method = heap;

--
