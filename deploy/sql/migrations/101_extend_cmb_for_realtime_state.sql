-- ===========================================================================
-- Object:   credential_model_bindings 扩展（防闪断）
-- Type:     ALTER TABLE
-- Schema:   public
-- Purpose:  为 anti-flap 双重验证提供状态标记。
--           只在"达到失败阈值、即将启动验证"时写一次，避免每次失败
--           都 UPDATE 触发 trg_notify_auto_route_cmb 造成 notify 风暴。
--           瞬态失败计数本身走 Redis 滑动窗口（credentialhealth.Recorder），
--           不落本表。
-- Created:  2026-06-30
-- ===========================================================================

-- 防闪断状态字段（仅验证触发时写入，非每次失败）
ALTER TABLE credential_model_bindings
ADD COLUMN IF NOT EXISTS transient_failure_count INTEGER DEFAULT 0,
ADD COLUMN IF NOT EXISTS pending_verification BOOLEAN DEFAULT false;

-- 仅查询 pending_verification=true 的行：辅助运维查看"哪些在验证中"。
CREATE INDEX IF NOT EXISTS idx_cmb_pending_verification
ON credential_model_bindings(credential_id)
WHERE pending_verification = true;

COMMENT ON COLUMN credential_model_bindings.transient_failure_count IS '触发验证时的失败计数快照（非实时；实时计数在 Redis 滑动窗口）';
COMMENT ON COLUMN credential_model_bindings.pending_verification IS '是否有进行中的双重验证';
