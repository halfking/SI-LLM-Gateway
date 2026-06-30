-- Rollback for 102_extend_mps_for_verification.sql

ALTER TABLE model_probe_state
DROP COLUMN IF EXISTS verification_latency_2_ms,
DROP COLUMN IF EXISTS verification_latency_1_ms,
DROP COLUMN IF EXISTS verification_result_2,
DROP COLUMN IF EXISTS verification_result_1,
DROP COLUMN IF EXISTS verification_attempt_2_at,
DROP COLUMN IF EXISTS verification_attempt_1_at;
