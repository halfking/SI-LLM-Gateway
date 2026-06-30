// Package credentialhealth - anti_flap.go
//
// AntiFlap 防止瞬态失败导致 credential+model 被误判不可用。
//
// 设计要点（区别于 Checker 的持续失败检测）：
//   - 失败计数复用 Recorder 的 Redis 滑动窗口，不在每个失败请求上
//     UPDATE credential_model_bindings。cmb 表有 trg_notify_auto_route_cmb
//     AFTER UPDATE 触发器，每次 UPDATE 都会 pg_notify，若每次失败都落库
//     会造成 notify 风暴。
//   - 达到阈值时只 UPDATE 一次（置 pending_verification=true），随后
//     异步做两次独立探测（2s + 5s）二次确认。两次都失败才标记不可用。
//   - 探测委托给 bg.ProbeCredentialModel（协议感知，复用现有探测能力），
//     不在本包重写请求逻辑。
package credentialhealth

import (
	"context"
	"fmt"
	"log/slog"
	"sync"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// AntiFlapConfig 防闪断配置。
type AntiFlapConfig struct {
	WindowDuration   time.Duration // 失败计数窗口，默认 30s（短窗口，针对瞬态）
	FailureThreshold int           // 触发验证的失败次数，默认 3
	VerifyDelay1     time.Duration // 阈值触发后第一次探测的延迟，默认 2s
	VerifyDelay2     time.Duration // 第一次后到第二次探测的间隔，默认 3s
	ProbeTimeout     time.Duration // 单次探测超时，默认 10s
	MinNonNetErrors  int           // 达到阈值的非网络错误数（网络错误不计），默认 3
	EnableAntiFlap   bool          // 特性开关

	// InvalidateCandidateCache 在标记不可用后同步调用，让候选缓存立即失效。
	// 注入而非直接依赖 provider 包，避免 credentialhealth→provider 耦合。
	InvalidateCandidateCache func()
}

// DefaultAntiFlapConfig 默认配置。
func DefaultAntiFlapConfig() AntiFlapConfig {
	return AntiFlapConfig{
		WindowDuration:   30 * time.Second,
		FailureThreshold: 3,
		VerifyDelay1:     2 * time.Second,
		VerifyDelay2:     3 * time.Second,
		ProbeTimeout:     10 * time.Second,
		MinNonNetErrors:  3,
		EnableAntiFlap:   true,
	}
}

// AntiFlap 防闪断器。
type AntiFlap struct {
	recorder *Recorder // 复用滑动窗口做失败计数（只读 GetRecent）
	db       *pgxpool.Pool
	config   AntiFlapConfig
	probe    ProbeFunc

	// 防止同一 (cred,model) 重复启动验证
	mu            sync.Mutex
	verifications map[string]bool // key = "credID:model"
}

// ProbeFunc 同步探测 credential+model 是否可调用的函数签名。
type ProbeFunc func(ctx context.Context, credentialID int, model string) (ok bool, errMsg string)

// NewAntiFlap 创建防闪断器。recorder 用于读失败计数；probe 用于二次验证。
func NewAntiFlap(recorder *Recorder, db *pgxpool.Pool, config AntiFlapConfig, probe ProbeFunc) *AntiFlap {
	return &AntiFlap{
		recorder:      recorder,
		db:            db,
		config:        config,
		probe:         probe,
		verifications: make(map[string]bool),
	}
}

// Enabled 是否启用。
func (a *AntiFlap) Enabled() bool {
	return a != nil && a.config.EnableAntiFlap && a.recorder != nil && a.db != nil && a.probe != nil
}

// OnFailure 在请求失败后调用：读 Redis 滑动窗口的失败计数，达到阈值则触发双重验证。
// 不在此处写库——计数完全走 Recorder，避免每个失败请求都 UPDATE cmb。
func (a *AntiFlap) OnFailure(ctx context.Context, credentialID int, model string) error {
	if !a.Enabled() {
		return nil
	}

	// 读窗口内最近条目，统计非网络失败数。
	since := time.Now().Add(-a.config.WindowDuration)
	entries, err := a.recorder.GetRecent(ctx, credentialID, model, since)
	if err != nil {
		return fmt.Errorf("get recent: %w", err)
	}

	nonNet := 0
	for _, e := range entries {
		if !e.Success && e.ErrorKind != "network" {
			nonNet++
		}
	}
	if nonNet < a.config.FailureThreshold {
		return nil
	}

	// 达到阈值：去重地启动一次双重验证。
	key := fmt.Sprintf("%d:%s", credentialID, model)
	a.mu.Lock()
	if a.verifications[key] {
		a.mu.Unlock()
		return nil // 已有验证在进行
	}
	a.verifications[key] = true
	a.mu.Unlock()

	slog.Info("anti_flap: threshold reached, scheduling double verification",
		"credential_id", credentialID,
		"model", model,
		"non_network_failures", nonNet,
		"window", a.config.WindowDuration)

	go a.doubleVerify(credentialID, model)
	return nil
}

// OnSuccess 在请求成功后调用：清掉待验证标记（如有）。
// 成功本身已由 Recorder 记录，这里只清理 cmb 上的 pending 状态。
// 仅当 pending_verification=true 时才 UPDATE（避免成功路径也每次写库）。
func (a *AntiFlap) OnSuccess(ctx context.Context, credentialID int, model string) error {
	if !a.Enabled() {
		return nil
	}
	_, err := a.db.Exec(ctx, `
		UPDATE credential_model_bindings cmb
		SET pending_verification   = FALSE,
		    transient_failure_count = 0
		FROM provider_models pm
		WHERE pm.id = cmb.provider_model_id
		  AND cmb.credential_id = $1
		  AND COALESCE(pm.outbound_model_name, pm.raw_model_name) = $2
		  AND cmb.pending_verification = TRUE
	`, credentialID, model)
	if err != nil {
		return fmt.Errorf("clear pending verification: %w", err)
	}
	return nil
}

// doubleVerify 两次探测，间隔 VerifyDelay1 / VerifyDelay2。两次都失败才标记不可用。
func (a *AntiFlap) doubleVerify(credentialID int, model string) {
	defer func() {
		key := fmt.Sprintf("%d:%s", credentialID, model)
		a.mu.Lock()
		delete(a.verifications, key)
		a.mu.Unlock()
	}()

	// 置 pending_verification=true，便于运维查看"哪些在验证中"。只写一次。
	ctx := context.Background()
	if _, err := a.db.Exec(ctx, `
		UPDATE credential_model_bindings cmb
		SET pending_verification = TRUE,
		    transient_failure_count = $3
		FROM provider_models pm
		WHERE pm.id = cmb.provider_model_id
		  AND cmb.credential_id = $1
		  AND COALESCE(pm.outbound_model_name, pm.raw_model_name) = $2
		  AND cmb.available = TRUE
	`, credentialID, model, a.config.FailureThreshold); err != nil {
		slog.Warn("anti_flap: set pending_verification failed", "credential_id", credentialID, "model", model, "error", err)
		// 仍继续探测：pending 标记只是可观测性，不阻断验证逻辑。
	}

	ok1, err1 := a.probeOnce(ctx, 1, credentialID, model)
	if ok1 {
		slog.Info("anti_flap: first probe succeeded, aborting", "credential_id", credentialID, "model", model)
		a.clearPending(ctx, credentialID, model)
		return
	}

	ok2, err2 := a.probeOnce(ctx, 2, credentialID, model)
	if ok2 {
		slog.Info("anti_flap: second probe succeeded, aborting", "credential_id", credentialID, "model", model)
		a.clearPending(ctx, credentialID, model)
		return
	}

	slog.Warn("anti_flap: both probes failed, marking unavailable",
		"credential_id", credentialID, "model", model,
		"error1", err1, "error2", err2)
	if err := a.markUnavailable(ctx, credentialID, model, "anti_flap_verified"); err != nil {
		slog.Error("anti_flap: mark unavailable failed", "credential_id", credentialID, "model", model, "error", err)
	}
}

// probeOnce 在指定延迟后做一次探测，并把结果记到 model_probe_state。返回 (ok, errMsg)。
func (a *AntiFlap) probeOnce(ctx context.Context, attempt int, credentialID int, model string) (bool, string) {
	delay := a.config.VerifyDelay1
	if attempt == 2 {
		delay = a.config.VerifyDelay2
	}
	select {
	case <-time.After(delay):
	case <-ctx.Done():
		return false, "ctx canceled before probe"
	}

	pctx, cancel := context.WithTimeout(ctx, a.config.ProbeTimeout)
	defer cancel()
	start := time.Now()
	ok, errMsg := a.probe(pctx, credentialID, model)
	latency := int(time.Since(start).Milliseconds())

	if recordErr := a.recordVerification(ctx, credentialID, model, attempt, ok, latency); recordErr != nil {
		slog.Warn("anti_flap: record verification failed",
			"credential_id", credentialID, "model", model, "attempt", attempt, "error", recordErr)
	}
	return ok, errMsg
}

// recordVerification 把单次探测结果写到 model_probe_state（UPSERT：行不存在则插入）。
func (a *AntiFlap) recordVerification(ctx context.Context, credentialID int, model string, attempt int, ok bool, latencyMs int) error {
	var setClause string
	if attempt == 1 {
		setClause = "verification_attempt_1_at = now(), verification_result_1 = $3, verification_latency_1_ms = $4"
	} else {
		setClause = "verification_attempt_2_at = now(), verification_result_2 = $3, verification_latency_2_ms = $4"
	}
	// ON CONFLICT 保证行一定存在（model_probe_state 主键为 credential_id+raw_model_name）。
	// 用 upsert 而非纯 UPDATE，避免 probeOne 验证记录因行不存在而丢失。
	tag, err := a.db.Exec(ctx, `
		INSERT INTO model_probe_state (credential_id, raw_model_name)
		VALUES ($1, $2)
		ON CONFLICT (credential_id, raw_model_name) DO NOTHING
	`, credentialID, model)
	if err != nil {
		return fmt.Errorf("ensure probe row: %w", err)
	}
	_ = tag

	_, err = a.db.Exec(ctx, fmt.Sprintf(`
		UPDATE model_probe_state
		SET %s
		WHERE credential_id = $1 AND raw_model_name = $2
	`, setClause), credentialID, model, ok, latencyMs)
	if err != nil {
		return fmt.Errorf("record verification: %w", err)
	}
	return nil
}

// clearPending 清除 pending 标记（验证中途有成功探测时调用）。
func (a *AntiFlap) clearPending(ctx context.Context, credentialID int, model string) {
	_, _ = a.db.Exec(ctx, `
		UPDATE credential_model_bindings cmb
		SET pending_verification   = FALSE,
		    transient_failure_count = 0
		FROM provider_models pm
		WHERE pm.id = cmb.provider_model_id
		  AND cmb.credential_id = $1
		  AND COALESCE(pm.outbound_model_name, pm.raw_model_name) = $2
	`, credentialID, model)
}

// markUnavailable 标记 credential+model 不可用，并镜像到 model_offers、失效候选缓存——
// 与 Checker.markDegraded 保持一致，确保路由层与管理 UI 同步。
func (a *AntiFlap) markUnavailable(ctx context.Context, credentialID int, model, reason string) error {
	recoverAt := time.Now().Add(2 * time.Hour)

	tag, err := a.db.Exec(ctx, `
		UPDATE credential_model_bindings cmb
		SET available              = FALSE,
		    unavailable_reason     = $3,
		    unavailable_at         = now(),
		    unavailable_recover_at = $4,
		    pending_verification   = FALSE,
		    transient_failure_count = 0,
		    updated_at             = now()
		FROM provider_models pm
		WHERE pm.id = cmb.provider_model_id
		  AND cmb.credential_id = $1
		  AND COALESCE(pm.outbound_model_name, pm.raw_model_name) = $2
		  AND cmb.available = TRUE
		  AND COALESCE(cmb.admin_protected, FALSE) = FALSE
		  AND COALESCE(cmb.unavailable_reason, '') NOT LIKE 'manual%%'
	`, credentialID, model, reason, recoverAt)
	if err != nil {
		return fmt.Errorf("update cmb: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return nil // 已不可用或被 admin 保护，无需处理
	}

	// 镜像到 model_offers（admin UI / test-route 视图）。
	if _, moErr := a.db.Exec(ctx, `
		UPDATE model_offers mo
		SET available              = FALSE,
		    unavailable_reason     = $3,
		    unavailable_at         = now(),
		    unavailable_recover_at = $4
		FROM provider_models pm
		WHERE pm.raw_model_name = mo.raw_model_name
		  AND pm.id IN (
		      SELECT cmb.provider_model_id
		      FROM credential_model_bindings cmb
		      WHERE cmb.credential_id = $1
		        AND cmb.unavailable_reason = $3
		  )
		  AND mo.credential_id = $1
		  AND mo.available = TRUE
		  AND COALESCE(mo.admin_protected, FALSE) = FALSE
	`, credentialID, model, reason, recoverAt); moErr != nil {
		slog.Warn("anti_flap: model_offers mirror failed",
			"credential_id", credentialID, "model", model, "error", moErr)
	}

	// 失效候选缓存，让路由层立刻看到新状态（注入回调，避免耦合 provider）。
	if a.config.InvalidateCandidateCache != nil {
		a.config.InvalidateCandidateCache()
	}

	slog.Warn("anti_flap: marked credential unavailable",
		"credential_id", credentialID, "model", model,
		"reason", reason, "recover_at", recoverAt)
	return nil
}
