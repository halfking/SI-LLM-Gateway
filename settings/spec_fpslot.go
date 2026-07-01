package settings

// spec_fpslot.go — Fingerprint slot pool configuration settings.
// 2026-07-01: Added to support runtime tuning of slot concurrency limits
// and preemption thresholds via the admin UI.

func FpSlotSpecs() []*Spec {
	min1 := 1.0
	max100 := 100.0
	min60 := 60.0
	max1800 := 1800.0
	min300 := 300.0
	max3600 := 3600.0
	max50 := 50.0
	
	return []*Spec{
		{
			Key:      "llmgw_fp_slot_enabled",
			EnvName:  "LLM_GATEWAY_ENABLE_CREDENTIAL_FP_SLOTS",
			Type:     TypeBool,
			Scope:    ScopePlatform,
			Category: CategorySecurity,
			Default:  true,
			Description: "启用指纹槽池（Fingerprint Slot Pool）。" +
				"关闭后所有凭据将使用无限制模式，失去身份隔离能力。",
			DangerLevel:   Warning,
			HotReload:     false, // 需要重启生效
			Observability: "/api/credentials/{id}/slots",
		},
		{
			Key:      "llmgw_fp_slot_default_limit",
			EnvName:  "LLM_GATEWAY_DEFAULT_CREDENTIAL_CONCURRENCY",
			Type:     TypeFloat,
			Scope:    ScopePlatform,
			Category: CategorySecurity,
			Default:  20.0,
			Min:      &min1,
			Max:      &max100,
			Description: "每个凭据的默认指纹槽数量。" +
				"数据库中未明确设置 fp_slot_limit 的凭据将使用此值。" +
				"2026-06-24: 从 5 提升到 20，减少槽位争抢。" +
				"注意：修改后需重启进程生效（启动时一次性读取）。",
			DangerLevel:   Safe,
			HotReload:     false, // credentialfpslot.Manager.cfg 启动时固定，无热重载入口
			Observability: "/api/credentials/{id}/slots",
		},
		{
			Key:      "llmgw_fp_slot_active_gate_seconds",
			EnvName:  "LLM_GATEWAY_CREDENTIAL_FP_SLOT_ACTIVE_GATE_SECONDS",
			Type:     TypeFloat,
			Scope:    ScopePlatform,
			Category: CategorySecurity,
			Default:  300.0,
			Min:      &min60,
			Max:      &max1800,
			Description: "活跃槽位保护时间（秒）。" +
				"持有者在此时间内有活动的槽位不会被抢占。" +
				"默认 300 秒（5 分钟）。" +
				"注意：修改后需重启进程生效（启动时一次性读取）。",
			DangerLevel:   Safe,
			HotReload:     false,
			Observability: "/api/credentials/{id}/slots",
		},
		{
			Key:      "llmgw_fp_slot_reclaim_idle_seconds",
			EnvName:  "LLM_GATEWAY_CREDENTIAL_FP_SLOT_RECLAIM_IDLE_SECONDS",
			Type:     TypeFloat,
			Scope:    ScopePlatform,
			Category: CategorySecurity,
			Default:  1800.0,
			Min:      &min300,
			Max:      &max3600,
			Description: "后台回收器的空闲阈值（秒）。" +
				"槽位闲置超过此时间后，后台 goroutine 将主动删除。" +
				"默认 1800 秒（30 分钟）。" +
				"注意：修改后需重启进程生效（回收循环启动时固定读取）。",
			DangerLevel:   Safe,
			HotReload:     false,
			Observability: "/api/credentials/{id}/slots",
		},
		{
			Key:      "llmgw_fp_slot_max_inflight_per_slot",
			EnvName:  "LLM_GATEWAY_CREDENTIAL_FP_SLOT_MAX_INFLIGHT_PER_SLOT",
			Type:     TypeFloat,
			Scope:    ScopePlatform,
			Category: CategorySecurity,
			Default:  10.0,
			Min:      &min1,
			Max:      &max50,
			Description: "单个指纹槽的最大并发请求数。" +
				"防止单个客户端独占槽位导致其他客户端无法获取槽位。" +
				"2026-07-01: 新增，修复 minimax-m3 被占满问题。" +
				"当同一持有者的并发数达到此限制时，新请求将 fallback 到 LRU 路径获取新槽位。" +
				"建议值：10（默认）对于大多数场景已足够；20-50 适用于高并发单客户端场景。" +
				"注意：修改后需重启进程生效（启动时一次性读取）。",
			DangerLevel:   Safe,
			HotReload:     false,
			Observability: "/api/credentials/{id}/slots",
		},
	}
}
