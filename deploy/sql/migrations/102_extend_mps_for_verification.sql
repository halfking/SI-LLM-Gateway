-- ===========================================================================
-- Object:   model_probe_state 扩展（双重验证结果）
-- Type:     ALTER TABLE
-- Schema:   public
-- Purpose:  记录 anti-flap 双重验证的两次探测结果，用于审计与可观测性。
-- Created:  2026-06-30
-- ===========================================================================

ALTER TABLE model_probe_state
ADD COLUMN IF NOT EXISTS verification_attempt_1_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS verification_attempt_2_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS verification_result_1 BOOLEAN,
ADD COLUMN IF NOT EXISTS verification_result_2 BOOLEAN,
ADD COLUMN IF NOT EXISTS verification_latency_1_ms INTEGER,
ADD COLUMN IF NOT EXISTS verification_latency_2_ms INTEGER;

COMMENT ON COLUMN model_probe_state.verification_attempt_1_at IS '防闪断第一次验证时间（阈值触发后约2秒）';
COMMENT ON COLUMN model_probe_state.verification_attempt_2_at IS '防闪断第二次验证时间（第一次后约3秒）';
COMMENT ON COLUMN model_probe_state.verification_result_1 IS '第一次验证结果';
COMMENT ON COLUMN model_probe_state.verification_result_2 IS '第二次验证结果';
