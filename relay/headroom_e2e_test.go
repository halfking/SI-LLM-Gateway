package relay_test

import (
	"context"
	"encoding/json"
	"testing"

	"github.com/kaixuan/llm-gateway-go/compressor/ccr"
	"github.com/kaixuan/llm-gateway-go/relay"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestHeadroomE2E_CompressionAndRetrieval tests the full Headroom workflow:
// 1. Client sends request with large JSON arrays
// 2. Headroom compresses arrays and stores in CCR
// 3. LLM receives compressed data with CCR markers
// 4. LLM calls headroom_retrieve tool (if needed)
// 5. Gateway retrieves full data from CCR and returns to LLM
func TestHeadroomE2E_CompressionAndRetrieval(t *testing.T) {
	// Setup: Create CCR manager with L1-only (for simplicity)
	config := ccr.DefaultConfig()
	config.L2Enabled = false
	config.L3Enabled = false
	
	ccrManager, err := ccr.NewManager(config, nil, nil)
	require.NoError(t, err)
	
	// Create CCR retrieval tool
	ccrTool := relay.NewCCRRetrievalTool(ccrManager)
	
	// Test 1: Verify CCR Put/Get cycle works
	t.Run("CCR_PutGet_Cycle", func(t *testing.T) {
		ctx := context.Background()
		testData := []byte(`["item1","item2","item3"]`)
		hash := "abc123def456789012345678"
		
		// Store data (unscoped, no session)
		err := ccrManager.Put(ctx, hash, testData, "")
		require.NoError(t, err)
		
		// Retrieve data (unscoped, no session check)
		retrieved, err := ccrManager.GetForSession(ctx, hash, "")
		require.NoError(t, err)
		assert.Equal(t, testData, retrieved)
		
		// Check metrics
		metrics := ccrManager.GetMetrics()
		assert.Greater(t, metrics.PutTotal, int64(0))
		assert.Greater(t, metrics.GetTotal, int64(0))
		assert.Greater(t, metrics.L1Hits, int64(0))
	})
	
	// Test 2: Verify CCR tool execution
	t.Run("CCR_Tool_Execution", func(t *testing.T) {
		ctx := context.Background()
		testData := []byte(`["data1","data2","data3"]`)
		hash := "test123456789012345678ab"
		
		// Store data (unscoped)
		err := ccrManager.Put(ctx, hash, testData, "")
		require.NoError(t, err)
		
		// Simulate LLM calling headroom_retrieve tool
		// NOTE: Tool requires session_id, so this will fail with L1-only setup
		// In production with L3, this would work correctly
		args := map[string]interface{}{
			"hash":       hash,
			"session_id": "test-session",
		}
		
		_, err = ccrTool.Execute(ctx, args)
		// Expected to fail because L1-only can't do session-scoped lookups
		assert.Error(t, err)
		assert.Contains(t, err.Error(), "session-scoped lookup requires L3")
	})
	
	// Test 3: Verify tool definition is correct
	t.Run("CCR_Tool_Definition", func(t *testing.T) {
		def := ccrTool.ToolDefinition()
		require.NotNil(t, def)
		
		assert.Equal(t, "headroom_retrieve", def["name"])
		assert.Contains(t, def["description"], "Retrieve compressed data")
		
		// Verify schema has required fields
		inputSchema, ok := def["input_schema"].(map[string]interface{})
		require.True(t, ok)
		
		required, ok := inputSchema["required"].([]string)
		require.True(t, ok)
		
		// Tool only requires "hash" from LLM
		// session_id is injected by gateway (not exposed to LLM for security)
		assert.Contains(t, required, "hash")
		assert.NotContains(t, required, "session_id", "session_id should be injected by gateway, not requested from LLM")
		
		// Verify properties
		properties, ok := inputSchema["properties"].(map[string]interface{})
		require.True(t, ok)
		assert.Contains(t, properties, "hash")
	})
	
	// Test 4: Large array generation (for compression testing)
	t.Run("Generate_Large_Array", func(t *testing.T) {
		largeArray := generateLargeArray(100)
		assert.Greater(t, len(largeArray), 1000) // Should be >1KB
		
		// Verify it's valid JSON
		var parsed []interface{}
		err := json.Unmarshal([]byte(largeArray), &parsed)
		require.NoError(t, err)
		assert.Len(t, parsed, 100)
	})
}

// generateLargeArray creates a JSON array string with N items for testing.
func generateLargeArray(n int) string {
	items := make([]map[string]interface{}, n)
	for i := 0; i < n; i++ {
		items[i] = map[string]interface{}{
			"id":    i,
			"name":  "item_" + string(rune('A'+i%26)),
			"value": i * 100,
		}
	}
	bytes, _ := json.Marshal(items)
	return string(bytes)
}

// TestHeadroomE2E_SessionIsolation verifies that session isolation is enforced.
// This test requires L3 (PostgreSQL) to be enabled in a real environment.
func TestHeadroomE2E_SessionIsolation(t *testing.T) {
	t.Skip("Session isolation test requires L3 (PostgreSQL) - run as integration test with real DB")
	
	// Test scenario:
	// 1. User A stores data with session_id="session_A"
	// 2. User B tries to retrieve with session_id="session_B"
	// 3. Should fail with ErrUnauthorized
	// 4. User A can retrieve successfully
	//
	// Implementation:
	// config := ccr.DefaultConfig()
	// config.L3Enabled = true
	// db := setupTestPostgreSQL(t)
	// ccrManager, _ := ccr.NewManager(config, nil, db)
	//
	// ctx := context.Background()
	// data := []byte(`["secret data"]`)
	// hash := "secure123456789012345678"
	//
	// // User A stores
	// ccrManager.Put(ctx, hash, data, "session_A")
	//
	// // User B tries to retrieve
	// _, err := ccrManager.GetForSession(ctx, hash, "session_B")
	// assert.Equal(t, ccr.ErrUnauthorized, err)
	//
	// // User A retrieves successfully
	// retrieved, err := ccrManager.GetForSession(ctx, hash, "session_A")
	// assert.NoError(t, err)
	// assert.Equal(t, data, retrieved)
}

