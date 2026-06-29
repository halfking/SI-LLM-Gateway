-- ===========================================================================
-- Object:   credit_ledger_2026_08
-- Type:     TABLE
-- Schema:   public
-- Source:   full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: credit_ledger_2026_08; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.credit_ledger_2026_08 (
    id bigint DEFAULT nextval('public.credit_ledger_partitioned_id_seq'::regclass) NOT NULL,
    tenant_id character varying NOT NULL,
    entry_type character varying NOT NULL,
    amount bigint NOT NULL,
    balance_after bigint NOT NULL,
    ref_type character varying,
    ref_id character varying,
    note text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    pool character varying
);


--
