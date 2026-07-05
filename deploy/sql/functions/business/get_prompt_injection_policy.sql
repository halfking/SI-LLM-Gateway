-- ============================================
-- Function: get_prompt_injection_policy
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE FUNCTION public.get_prompt_injection_policy(p_tenant_id character varying) RETURNS public.prompt_injection_policies
    LANGUAGE plpgsql STABLE
    AS $$ DECLARE v_policy prompt_injection_policies; BEGIN SELECT * INTO v_policy FROM prompt_injection_policies WHERE tenant_id = p_tenant_id; RETURN v_policy; END; $$;



