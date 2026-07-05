-- ============================================
-- View: v_fp_slot_policy
-- Generated: 2026-07-05
-- Source: Test database
-- ============================================

CREATE VIEW public.v_fp_slot_policy AS
 SELECT COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::boolean AS bool
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_enabled'::text)), true) AS enabled,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_max_per_credential'::text)), 100) AS max_per_credential,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::numeric AS "numeric"
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_default_ratio'::text)), 0.25) AS default_ratio,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_client_fingerprint_ttl_days'::text)), 30) AS client_ttl_days,
    COALESCE(( SELECT ((settings_kv.value #>> '{}'::text[]))::integer AS int4
           FROM public.settings_kv
          WHERE ((settings_kv.key)::text = 'llmgw_fp_slot_max_total_clients'::text)), 10000) AS max_total_clients;
