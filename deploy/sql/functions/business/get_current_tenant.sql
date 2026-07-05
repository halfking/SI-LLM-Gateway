-- ============================================
-- Function: get_current_tenant
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.get_current_tenant() RETURNS text
    LANGUAGE sql STABLE
    AS $$ SELECT COALESCE(NULLIF(current_setting('app.current_tenant', true), ''), 'default'); $$;



