-- ============================================
-- Function: update_provider_settings_updated_at
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.update_provider_settings_updated_at() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;



