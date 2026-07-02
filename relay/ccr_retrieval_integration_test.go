package relay

import (
	"context"
	"testing"

	"github.com/kaixuan/llm-gateway-go/compressor/ccr"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestCCRRetrievalToolMissingSessionID verifies security: no session = no data
func TestCCRRetrievalToolMissingSessionID(t *testing.T) {
	config := ccr.DefaultConfig()
	config.L2Enabled = false
	config.L3Enabled = false
	
	manager, err := ccr.NewManager(config, nil, nil)
	require.NoError(t, err)
	
	tool := NewCCRRetrievalTool(manager)
	ctx := context.Background()
	
	// Attempt retrieval without session_id
	args := map[string]interface{}{
		"hash": "abc123def456789012345678",
	}
	_, err = tool.Execute(ctx, args)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "session_id is required")
}

// TestCCRRetrievalToolRequiresL3 verifies security enforcement:
// Session-scoped lookups require L3 (PostgreSQL) because L1/L2 can't validate sessionID.
func TestCCRRetrievalToolRequiresL3(t *testing.T) {
	// Setup: L1+L2 only (no L3)
	config := ccr.DefaultConfig()
	config.L3Enabled = false
	
	manager, err := ccr.NewManager(config, nil, nil)
	require.NoError(t, err)
	
	tool := NewCCRRetrievalTool(manager)
	ctx := context.Background()
	
	// Attempt session-scoped retrieval without L3
	args := map[string]interface{}{
		"hash":       "abc123def456789012345678",
		"session_id": "test-session-123",
	}
	_, err = tool.Execute(ctx, args)
	
	// Should fail with clear error message
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "session-scoped lookup requires L3")
}

// TestCCRToolInjection verifies tool definition is properly formatted
func TestCCRToolInjection(t *testing.T) {
	config := ccr.DefaultConfig()
	config.L2Enabled = false
	config.L3Enabled = false
	
	manager, err := ccr.NewManager(config, nil, nil)
	require.NoError(t, err)
	
	tool := NewCCRRetrievalTool(manager)
	
	// Verify tool metadata
	assert.Equal(t, "headroom_retrieve", tool.Name())
	assert.Contains(t, tool.Description(), "compressed data")
	assert.Contains(t, tool.Description(), "CCR hash")
	
	// Verify input schema
	schema := tool.InputSchema()
	assert.Equal(t, "object", schema["type"])
	
	props, ok := schema["properties"].(map[string]interface{})
	require.True(t, ok)
	
	hashProp, ok := props["hash"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "string", hashProp["type"])
	assert.Equal(t, "^[a-f0-9]{24}$", hashProp["pattern"])
	
	required, ok := schema["required"].([]string)
	require.True(t, ok)
	assert.Contains(t, required, "hash")
}
