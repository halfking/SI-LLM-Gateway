-- Rollback for 101_extend_cmb_for_realtime_state.sql

DROP INDEX IF EXISTS idx_cmb_pending_verification;

ALTER TABLE credential_model_bindings
DROP COLUMN IF EXISTS pending_verification,
DROP COLUMN IF EXISTS transient_failure_count;
