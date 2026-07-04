// Package telemetry provides partition routing logic for time-series tables.
package telemetry

import (
	"fmt"
	"time"
)

// partitionRouter 根据数据年龄动态选择目标分区表
//
// 架构设计（2026-07-04）：
//   - 热数据（最近 7 天）→ *_default 表（heap，支持频繁 UPSERT）
//   - 冷数据（7 天前）→ 当月分区表（heap，偶尔补录）
//   - 历史数据（上月及更早）→ 月度分区表（可能是 columnar，只读归档）
//
// 这样设计的好处：
//  1. 热数据快速访问（default 表索引小，查询快）
//  2. UPSERT 安全（大部分写入在 heap 表）
//  3. 所有分区 ATTACHED → SELECT 父表自动聚合所有数据
//  4. 无跨月中断（当月分区一直 ATTACHED）
type partitionRouter struct {
	hotDataWindow time.Duration // 热数据窗口期（默认 7 天）
}

func newPartitionRouter() *partitionRouter {
	return &partitionRouter{
		hotDataWindow: 7 * 24 * time.Hour,
	}
}

// getRequestLogsTable 根据 ts 返回应该写入的 request_logs 分区表名
func (r *partitionRouter) getRequestLogsTable(ts time.Time) string {
	return r.getPartitionTable("request_logs", ts)
}

// getUsageLedgerTable 根据 ts 返回应该写入的 usage_ledger 分区表名
func (r *partitionRouter) getUsageLedgerTable(ts time.Time) string {
	return r.getPartitionTable("usage_ledger", ts)
}

// getPartitionTable 核心路由逻辑
//
// 路由规则：
//   - age < 7 天且 age >= 0 → *_default（热数据）
//   - age < 0（未来时间戳） → *_default（异常数据）
//   - age >= 7 天 → *_YYYY_MM（冷数据，按 ts 的月份路由）
func (r *partitionRouter) getPartitionTable(baseTable string, ts time.Time) string {
	now := time.Now()
	age := now.Sub(ts)

	// 最近 7 天（热数据）→ *_default 表（heap，支持频繁 UPSERT）
	if age < r.hotDataWindow && age >= 0 {
		return baseTable + "_default"
	}

	// 未来时间戳（异常数据）→ *_default 表
	if age < 0 {
		return baseTable + "_default"
	}

	// 7 天前的数据（冷数据）→ 当月分区表（heap，偶尔补录）
	// 使用 ts 的月份，而不是 now 的月份（处理跨月补录场景）
	// 例如：2026-06-25 的数据 → request_logs_2026_06
	month := ts.Format("2006_01")
	return fmt.Sprintf("%s_%s", baseTable, month)
}

// 全局路由器实例
var defaultRouter = newPartitionRouter()
