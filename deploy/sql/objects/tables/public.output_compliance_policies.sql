-- ===========================================================================
-- Object:   output_compliance_policies
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: output_compliance_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.output_compliance_policies (
    id integer NOT NULL,
    tenant_id character varying(255) NOT NULL,
    enabled boolean DEFAULT true,
    enforcement_mode character varying(20) DEFAULT 'observe'::character varying,
    check_pii boolean DEFAULT true,
    check_toxicity boolean DEFAULT true,
    check_bias boolean DEFAULT false,
    check_hallucination boolean DEFAULT false,
    pii_threshold numeric(3,2) DEFAULT 0.7,
    toxicity_threshold numeric(3,2) DEFAULT 0.7,
    bias_threshold numeric(3,2) DEFAULT 0.6,
    hallucination_threshold numeric(3,2) DEFAULT 0.7,
    action_on_pii character varying(20) DEFAULT 'redact'::character varying,
    action_on_toxicity character varying(20) DEFAULT 'warn'::character varying,
    action_on_bias character varying(20) DEFAULT 'log'::character varying,
    action_on_hallucination character varying(20) DEFAULT 'log'::character varying,
    auto_redact boolean DEFAULT true,
    redact_email boolean DEFAULT true,
    redact_phone boolean DEFAULT true,
    redact_id_card boolean DEFAULT true,
    redact_credit_card boolean DEFAULT true,
    strict_mode boolean DEFAULT false,
    log_all_outputs boolean DEFAULT false,
    whitelist_patterns text[],
    total_checks integer DEFAULT 0,
    total_issues integer DEFAULT 0,
    total_redactions integer DEFAULT 0,
    last_check_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(255),
    updated_by character varying(255)
);


--
