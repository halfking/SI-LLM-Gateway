-- ===========================================================================
-- Object:   auto_tune_audit
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: auto_tune_audit; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.auto_tune_audit (
    id bigint NOT NULL,
    credential_id bigint NOT NULL,
    raw_model text DEFAULT ''::text NOT NULL,
    action text NOT NULL,
    old_limit integer,
    new_limit integer,
    reason text,
    peak_concurrent integer,
    p95_concurrent numeric(8,2),
    week_start timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    applied_by text
);


--
