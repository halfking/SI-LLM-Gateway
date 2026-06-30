-- Rollback for migration 057. Drops the partial index, then the column.
-- Note: archive-tier mirror (db/request_logs_archive_schema.go and
-- deploy/sql/migrations/910_request_logs_archive.sql) must be reverted
-- separately.

DROP INDEX IF EXISTS public.idx_request_logs_provider_model;
ALTER TABLE public.request_logs DROP COLUMN IF EXISTS provider_model;