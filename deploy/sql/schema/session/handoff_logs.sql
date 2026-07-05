-- ============================================
-- Table: handoff_logs
-- Category: session
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.handoff_logs (
    id integer NOT NULL,
    session_id character varying(64) NOT NULL,
    tenant_id character varying(64) NOT NULL,
    trigger_reason character varying(64) NOT NULL,
    tokens_at_handoff integer NOT NULL,
    context_window integer,
    handoff_prompt text,
    new_session_id character varying(64),
    created_at timestamp without time zone DEFAULT now()
);
