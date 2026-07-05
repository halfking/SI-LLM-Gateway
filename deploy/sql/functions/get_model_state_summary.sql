-- ============================================
-- Function: get_model_state_summary
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.get_model_state_summary(p_raw_model_name text) RETURNS TABLE(state text, priority text, count bigint, avg_success_rate numeric, next_probe_in_seconds integer)
    LANGUAGE sql STABLE
    AS $$
		    SELECT
		        sub.state::TEXT,
		        sub.priority::TEXT,
		        COUNT(*) as count,
		        ROUND(AVG(CASE WHEN sub.total_attempts > 0
		                       THEN sub.consecutive_successes::float / sub.total_attempts * 100
		                       ELSE NULL END)::numeric, 2) as avg_success_rate,
		        EXTRACT(EPOCH FROM MIN(sub.next_retry_at - NOW()))::INTEGER as next_probe_in_seconds
		    FROM (
		        SELECT
		            mps.state,
		            mps.consecutive_successes,
		            mps.total_attempts,
		            mps.next_retry_at,
		            CASE
		                WHEN mps.consecutive_failures >= 3 THEN 'urgent'
		                WHEN mps.state = 'suspicious' THEN 'suspicious'
		                WHEN mps.state IN ('failing', 'recovering') THEN 'failing'
		                ELSE 'watchdog'
		            END as priority
		        FROM model_probe_state mps
		        JOIN credentials c ON c.id = mps.credential_id
		        WHERE mps.raw_model_name = p_raw_model_name
		          AND COALESCE(c.status, 'active') = 'active'
		          AND COALESCE(c.lifecycle_status, 'active') = 'active'
		          AND COALESCE(c.manual_disabled, FALSE) = FALSE
		    ) sub
		    GROUP BY sub.state, sub.priority
		    ORDER BY
		        CASE sub.priority
		            WHEN 'urgent' THEN 1
		            WHEN 'suspicious' THEN 2
		            WHEN 'failing' THEN 3
		            WHEN 'watchdog' THEN 4
		            ELSE 5
		        END,
		        sub.state;
		$$;





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



