-- ===========================================================================
-- Object:   credential_model_peak_1m
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credential_model_peak_1m; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credential_model_peak_1m (
    bucket timestamp with time zone NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    peak_concurrent integer DEFAULT 0 NOT NULL,
    avg_concurrent numeric(8,2) DEFAULT 0 NOT NULL,
    sample_count integer DEFAULT 0 NOT NULL
);


--
