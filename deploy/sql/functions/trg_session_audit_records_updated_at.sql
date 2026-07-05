-- ============================================
-- Function: trg_session_audit_records_updated_at
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.trg_session_audit_records_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;



