package main

import (
	"context"
	"fmt"
	"log"

	"github.com/jackc/pgx/v5/pgxpool"
)

func main() {
	databaseURL := "postgres://llm_gateway:4Q92cFTaYY8Z3AO07XTBBH-1g7kceaxg@127.0.0.1:5432/llm_gateway?sslmode=disable&connect_timeout=30"
	
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		log.Fatal("parse config:", err)
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), cfg)
	if err != nil {
		log.Fatal("new pool:", err)
	}
	defer pool.Close()

	if err := pool.Ping(context.Background()); err != nil {
		log.Fatal("ping:", err)
	}
	fmt.Println("✓ postgres connected")

	// Test each schema migration one by one
	migrations := []struct {
		name string
		sql  string
	}{
		{"request_logs_quality_flags", `
			ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS quality_flags TEXT[] NOT NULL DEFAULT '{}';
		`},
		{"request_logs_quality_fix_actions", `
			ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS quality_fix_actions JSONB NOT NULL DEFAULT '{}'::jsonb;
		`},
		{"request_logs_quality_score", `
			ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS quality_score NUMERIC(3,2);
		`},
		{"idx_request_logs_quality_flags", `
			CREATE INDEX IF NOT EXISTS idx_request_logs_quality_flags
			    ON request_logs USING GIN (quality_flags)
			    WHERE cardinality(quality_flags) > 0;
		`},
		{"idx_request_logs_provider_quality", `
			CREATE INDEX IF NOT EXISTS idx_request_logs_provider_quality
			    ON request_logs (provider_id, quality_score, ts DESC)
			    WHERE quality_score IS NOT NULL;
		`},
		{"request_logs_upstream_finish_reason", `
			ALTER TABLE request_logs ADD COLUMN IF NOT EXISTS upstream_finish_reason TEXT;
		`},
		{"idx_request_logs_upstream_finish_reason", `
			CREATE INDEX IF NOT EXISTS idx_request_logs_upstream_finish_reason
			    ON request_logs (upstream_finish_reason, ts DESC)
			WHERE upstream_finish_reason IS NOT NULL
			      AND upstream_finish_reason <> '';
		`},
	}

	for _, mig := range migrations {
		fmt.Printf("Testing: %s\n", mig.name)
		_, err := pool.Exec(context.Background(), mig.sql)
		if err != nil {
			log.Fatalf("✗ FAILED at %s: %v", mig.name, err)
		}
		fmt.Printf("  ✓ ok\n")
	}

	fmt.Println("\n✓ All migrations passed")
}
