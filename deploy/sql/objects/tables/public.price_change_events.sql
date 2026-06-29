-- ===========================================================================
-- Object:   price_change_events
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: price_change_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.price_change_events (
    id bigint,
    old_plan_id bigint,
    new_plan_id bigint,
    delta_json jsonb,
    detected_at timestamp with time zone,
    notify_channel text,
    applied boolean
);


SET default_table_access_method = heap;

--
