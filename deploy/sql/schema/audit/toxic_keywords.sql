-- ============================================
-- Table: toxic_keywords
-- Category: audit
-- Generated: 2026-07-05
-- ============================================

CREATE TABLE public.toxic_keywords (
    id integer NOT NULL,
    keyword character varying(100) NOT NULL,
    category character varying(50) NOT NULL,
    severity integer NOT NULL,
    language character varying(10) DEFAULT 'zh'::character varying,
    enabled boolean DEFAULT true,
    created_at timestamp with time zone DEFAULT now(),
    CONSTRAINT toxic_keywords_severity_check CHECK (((severity >= 1) AND (severity <= 10)))
);
