-- ===========================================================================
-- Object:   prompt_injection_policies
-- Type:     TABLE
-- Schema:   public
-- Source:   184_full_schema.sql (pg_dump --schema-only)
-- ===========================================================================
-- Name: prompt_injection_policies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.prompt_injection_policies (
    id integer NOT NULL,
    tenant_id character varying(255) NOT NULL,
    enabled boolean DEFAULT true,
    detection_mode character varying(20) DEFAULT 'observe'::character varying,
    enable_basic_rules boolean DEFAULT true,
    enable_advanced_rules boolean DEFAULT true,
    enable_heuristics boolean DEFAULT true,
    enable_ml_model boolean DEFAULT false,
    score_threshold_log integer DEFAULT 3,
    score_threshold_warn integer DEFAULT 6,
    score_threshold_sanitize integer DEFAULT 8,
    score_threshold_block integer DEFAULT 10,
    action_on_low_risk character varying(20) DEFAULT 'log'::character varying,
    action_on_medium_risk character varying(20) DEFAULT 'warn'::character varying,
    action_on_high_risk character varying(20) DEFAULT 'block'::character varying,
    whitelist_patterns text[],
    whitelist_users text[],
    notify_on_detection boolean DEFAULT false,
    notification_webhook character varying(500),
    notification_email character varying(255),
    total_detections integer DEFAULT 0,
    total_blocks integer DEFAULT 0,
    last_detection_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now(),
    created_by character varying(255),
    updated_by character varying(255)
);


--
