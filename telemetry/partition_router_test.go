package telemetry

import (
	"testing"
	"time"
)

func TestPartitionRouter_GetPartitionTable(t *testing.T) {
	router := newPartitionRouter()
	now := time.Now()

	tests := []struct {
		name      string
		baseTable string
		ts        time.Time
		want      string
	}{
		{
			name:      "hot data (1 hour ago)",
			baseTable: "request_logs",
			ts:        now.Add(-1 * time.Hour),
			want:      "request_logs_default",
		},
		{
			name:      "hot data (6 days ago)",
			baseTable: "request_logs",
			ts:        now.Add(-6 * 24 * time.Hour),
			want:      "request_logs_default",
		},
		{
			name:      "boundary (exactly 7 days ago)",
			baseTable: "request_logs",
			ts:        now.Add(-7 * 24 * time.Hour),
			want:      now.Add(-7 * 24 * time.Hour).Format("request_logs_2006_01"),
		},
		{
			name:      "cold data (10 days ago)",
			baseTable: "request_logs",
			ts:        now.Add(-10 * 24 * time.Hour),
			want:      now.Add(-10 * 24 * time.Hour).Format("request_logs_2006_01"),
		},
		{
			name:      "future timestamp",
			baseTable: "request_logs",
			ts:        now.Add(1 * time.Hour),
			want:      "request_logs_default",
		},
		{
			name:      "usage_ledger hot data",
			baseTable: "usage_ledger",
			ts:        now.Add(-3 * 24 * time.Hour),
			want:      "usage_ledger_default",
		},
		{
			name:      "usage_ledger cold data",
			baseTable: "usage_ledger",
			ts:        now.Add(-15 * 24 * time.Hour),
			want:      now.Add(-15 * 24 * time.Hour).Format("usage_ledger_2006_01"),
		},
		{
			name:      "cross-month backfill (last month)",
			baseTable: "request_logs",
			ts:        time.Date(2026, 6, 25, 12, 0, 0, 0, time.UTC),
			want:      "request_logs_2026_06",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := router.getPartitionTable(tt.baseTable, tt.ts)
			if got != tt.want {
				t.Errorf("getPartitionTable() = %v, want %v", got, tt.want)
			}
		})
	}
}

func TestPartitionRouter_GetRequestLogsTable(t *testing.T) {
	router := newPartitionRouter()
	now := time.Now()

	// 热数据
	hotTS := now.Add(-3 * 24 * time.Hour)
	if got := router.getRequestLogsTable(hotTS); got != "request_logs_default" {
		t.Errorf("hot data: got %v, want request_logs_default", got)
	}

	// 冷数据
	coldTS := now.Add(-10 * 24 * time.Hour)
	expectedMonth := coldTS.Format("2006_01")
	expectedTable := "request_logs_" + expectedMonth
	if got := router.getRequestLogsTable(coldTS); got != expectedTable {
		t.Errorf("cold data: got %v, want %v", got, expectedTable)
	}
}

func TestPartitionRouter_GetUsageLedgerTable(t *testing.T) {
	router := newPartitionRouter()
	now := time.Now()

	// 热数据
	hotTS := now.Add(-5 * 24 * time.Hour)
	if got := router.getUsageLedgerTable(hotTS); got != "usage_ledger_default" {
		t.Errorf("hot data: got %v, want usage_ledger_default", got)
	}

	// 冷数据
	coldTS := now.Add(-20 * 24 * time.Hour)
	expectedMonth := coldTS.Format("2006_01")
	expectedTable := "usage_ledger_" + expectedMonth
	if got := router.getUsageLedgerTable(coldTS); got != expectedTable {
		t.Errorf("cold data: got %v, want %v", got, expectedTable)
	}
}

// TestPartitionRouter_HotDataWindowBoundary 验证 7 天边界的精确行为
func TestPartitionRouter_HotDataWindowBoundary(t *testing.T) {
	router := newPartitionRouter()
	now := time.Now()

	// 7 天 - 1 秒（应该还在热数据窗口内）
	almostSevenDays := now.Add(-7*24*time.Hour + 1*time.Second)
	if got := router.getRequestLogsTable(almostSevenDays); got != "request_logs_default" {
		t.Errorf("7 days - 1s: got %v, want request_logs_default", got)
	}

	// 7 天 + 1 秒（应该进入冷数据）
	justOverSevenDays := now.Add(-7*24*time.Hour - 1*time.Second)
	expectedMonth := justOverSevenDays.Format("2006_01")
	expectedTable := "request_logs_" + expectedMonth
	if got := router.getRequestLogsTable(justOverSevenDays); got != expectedTable {
		t.Errorf("7 days + 1s: got %v, want %v", got, expectedTable)
	}
}
