-- Rollback for migration 056. Drops the indexes and PK in reverse
-- order. None of these are referenced by a foreign key, so dropping
-- is safe (no dependent object will break).

DROP INDEX IF EXISTS public.idx_request_logs_ts_desc;
DROP INDEX IF EXISTS public.idx_model_aliases_lower_raw_name_status;

ALTER TABLE public.model_aliases
    DROP CONSTRAINT IF EXISTS model_aliases_pkey;

DROP INDEX IF EXISTS public.idx_cmb_credential_provider_model;
DROP INDEX IF EXISTS public.idx_provider_models_lower_raw_model_name;
DROP INDEX IF EXISTS public.idx_provider_models_lower_standardized_name;
DROP INDEX IF EXISTS public.idx_provider_models_canonical_id;