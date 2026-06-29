-- ===========================================================================
-- Object:   tuning_params
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: tuning_params; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tuning_params (
    key text NOT NULL,
    value jsonb NOT NULL,
    category text NOT NULL,
    source text DEFAULT 'default'::text NOT NULL,
    confidence numeric(4,3) DEFAULT 1.0 NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    description text,
    applied_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL
);


--
