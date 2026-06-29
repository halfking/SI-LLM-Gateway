DROP INDEX IF EXISTS idx_request_logs_upstream_status;
ALTER TABLE request_logs DROP COLUMN IF EXISTS upstream_status_code;