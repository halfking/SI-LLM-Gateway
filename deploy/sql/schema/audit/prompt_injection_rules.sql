-- ============================================
-- Table: prompt_injection_rules
-- Category: audit
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.prompt_injection_rules (
    id integer NOT NULL,
    rule_name character varying(100) NOT NULL,
    rule_type character varying(50) NOT NULL,
    category character varying(50) NOT NULL,
    pattern text NOT NULL,
    description text,
    severity integer NOT NULL,
    enabled boolean DEFAULT true,
    case_sensitive boolean DEFAULT false,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    CONSTRAINT prompt_injection_rules_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);
