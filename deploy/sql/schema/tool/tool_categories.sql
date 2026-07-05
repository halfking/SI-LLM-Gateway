-- ============================================
-- Table: tool_categories
-- Category: tool
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.tool_categories (
    id character varying(64) NOT NULL,
    name character varying(128) NOT NULL,
    description text,
    enabled boolean DEFAULT true,
    display_order integer DEFAULT 0,
    created_at timestamp with time zone DEFAULT now(),
    updated_at timestamp with time zone DEFAULT now()
);
