-- ============================================
-- Function: key_applications_set_updated_at
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.key_applications_set_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;



