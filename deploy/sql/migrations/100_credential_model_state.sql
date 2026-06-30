-- ===========================================================================
-- Object:   credential_model_state
-- Type:     TABLE
-- Schema:   public
-- Purpose:  统一管理credential+model的实时状态
-- Created:  2026-06-30
-- ===========================================================================

CREATE TABLE IF NOT EXISTS public.credential_model_state (
    id BIGSERIAL PRIMARY KEY,
    credential_id BIGINT NOT NULL,
    model TEXT NOT NULL,
    
    -- 状态字段
    state TEXT NOT NULL DEFAULT 'unknown', 
        -- 'healthy', 'degraded', 'unavailable', 'probing', 'unknown'
    available BOOLEAN NOT NULL DEFAULT true,
    
    -- 统计字段
    total_requests INTEGER DEFAULT 0,
    success_count INTEGER DEFAULT 0,
    failure_count INTEGER DEFAULT 0,
    consecutive_failures INTEGER DEFAULT 0,
    consecutive_successes INTEGER DEFAULT 0,
    success_rate NUMERIC(5,2),
    
    -- 最近错误
    last_error_kind TEXT,
    last_error_at TIMESTAMPTZ,
    
    -- 最近成功
    last_success_at TIMESTAMPTZ,
    last_latency_ms INTEGER,
    
    -- 探测相关
    last_probe_at TIMESTAMPTZ,
    last_probe_success BOOLEAN,
    last_probe_latency_ms INTEGER,
    probe_consecutive_failures INTEGER DEFAULT 0,
    probe_consecutive_successes INTEGER DEFAULT 0,
    next_probe_at TIMESTAMPTZ,
    probe_interval_sec INTEGER DEFAULT 30,
    
    -- 防闪断
    transient_failure_count INTEGER DEFAULT 0,
    transient_failure_window_start TIMESTAMPTZ,
    pending_verification BOOLEAN DEFAULT false,
    verification_scheduled_at TIMESTAMPTZ,
    
    -- 降级相关
    degraded_at TIMESTAMPTZ,
    degraded_reason TEXT,
    unavailable_at TIMESTAMPTZ,
    unavailable_reason TEXT,
    unavailable_until TIMESTAMPTZ,
    
    -- 元数据
    created_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    
    UNIQUE(credential_id, model),
    
    CONSTRAINT chk_state CHECK (state IN ('healthy', 'degraded', 'unavailable', 'probing', 'unknown')),
    CONSTRAINT chk_success_rate CHECK (success_rate IS NULL OR (success_rate >= 0 AND success_rate <= 100))
);

-- 索引
CREATE INDEX IF NOT EXISTS idx_cms_available ON credential_model_state(available, state) WHERE available = true;
CREATE INDEX IF NOT EXISTS idx_cms_model ON credential_model_state(model) WHERE available = true;
CREATE INDEX IF NOT EXISTS idx_cms_next_probe ON credential_model_state(next_probe_at) WHERE next_probe_at IS NOT NULL AND next_probe_at <= NOW() + INTERVAL '1 hour';
CREATE INDEX IF NOT EXISTS idx_cms_credential ON credential_model_state(credential_id);
CREATE INDEX IF NOT EXISTS idx_cms_state ON credential_model_state(state, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_cms_verification ON credential_model_state(pending_verification, verification_scheduled_at) WHERE pending_verification = true;

-- 更新updated_at的触发器
CREATE OR REPLACE FUNCTION update_cms_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_cms_updated_at
    BEFORE UPDATE ON credential_model_state
    FOR EACH ROW
    EXECUTE FUNCTION update_cms_updated_at();

-- 注释
COMMENT ON TABLE credential_model_state IS '统一管理credential+model组合的实时健康状态';
COMMENT ON COLUMN credential_model_state.state IS '状态: healthy/degraded/unavailable/probing/unknown';
COMMENT ON COLUMN credential_model_state.available IS '是否可用于路由';
COMMENT ON COLUMN credential_model_state.consecutive_failures IS '连续失败次数（请求）';
COMMENT ON COLUMN credential_model_state.probe_consecutive_failures IS '连续探测失败次数';
COMMENT ON COLUMN credential_model_state.transient_failure_count IS '瞬态窗口内失败次数（防闪断）';
COMMENT ON COLUMN credential_model_state.pending_verification IS '是否有待执行的双重验证';
