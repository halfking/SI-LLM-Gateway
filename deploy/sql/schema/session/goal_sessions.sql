-- ============================================
-- Table: goal_sessions
-- Category: session
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.goal_sessions (
    id integer NOT NULL,
    session_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    state character varying(32) DEFAULT 'active'::character varying NOT NULL,
    original_goal text NOT NULL,
    retry_count integer DEFAULT 0,
    decision_count integer DEFAULT 0,
    auto_continue_count integer DEFAULT 0,
    last_activity_at timestamp without time zone DEFAULT now(),
    completed_at timestamp without time zone,
    audit_result jsonb,
    created_at timestamp without time zone DEFAULT now()
);
