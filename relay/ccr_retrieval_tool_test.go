package relay

import (
	"context"
	"testing"

	"github.com/alicebob/miniredis/v2"
	"github.com/kaixuan/llm-gateway-go/compressor/ccr"
	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func setupTestCCRManager(t *testing.T) (*ccr.Manager, func()) {
	mr := miniredis.RunT(t)
	redisClient := redis.NewClient(&redis.Options{
		Addr: mr.Addr(),
	})

	config := ccr.DefaultConfig()
	config.L3Enabled = false
	manager, err := ccr.NewManager(config, redisClient, nil)
	require.NoError(t, err)

	cleanup := func() {
		manager.Close()
		redisClient.Close()
		mr.Close()
	}

	return manager, cleanup
}

func TestCCRRetrievalTool_Name(t *testing.T) {
	tool := NewCCRRetrievalTool(nil)
	assert.Equal(t, "headroom_retrieve", tool.Name())
}

func TestCCRRetrievalTool_Description(t *testing.T) {
	tool := NewCCRRetrievalTool(nil)
	desc := tool.Description()
	assert.Contains(t, desc, "CCR hash")
	assert.Contains(t, desc, "<<ccr:")
}

func TestCCRRetrievalTool_InputSchema(t *testing.T) {
	tool := NewCCRRetrievalTool(nil)
	schema := tool.InputSchema()

	assert.Equal(t, "object", schema["type"])
	props, ok := schema["properties"].(map[string]interface{})
	require.True(t, ok)
	
	hashProp, ok := props["hash"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "string", hashProp["type"])
}

func TestCCRRetrievalTool_Execute_Success(t *testing.T) {
	manager, cleanup := setupTestCCRManager(t)
	defer cleanup()

	tool := NewCCRRetrievalTool(manager)
	ctx := context.Background()

	// Store test data
	hash := "abc123def456789012345678"
	testData := []byte(`["item1", "item2", "item3"]`)
	err := manager.Put(ctx, hash, testData, "test_session")
	require.NoError(t, err)

	// Execute retrieval
	args := map[string]interface{}{
		"hash": hash,
	}
	result, err := tool.Execute(ctx, args)
	require.NoError(t, err)
	assert.NotNil(t, result)
}

func TestCCRRetrievalTool_Execute_InvalidHash(t *testing.T) {
	manager, cleanup := setupTestCCRManager(t)
	defer cleanup()

	tool := NewCCRRetrievalTool(manager)
	ctx := context.Background()

	tests := []struct {
		name string
		args map[string]interface{}
		want string
	}{
		{
			name: "missing hash",
			args: map[string]interface{}{},
			want: "hash parameter is required",
		},
		{
			name: "wrong length",
			args: map[string]interface{}{"hash": "short"},
			want: "invalid hash format",
		},
		{
			name: "wrong type",
			args: map[string]interface{}{"hash": 123},
			want: "hash parameter is required",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			_, err := tool.Execute(ctx, tt.args)
			assert.Error(t, err)
			assert.Contains(t, err.Error(), tt.want)
		})
	}
}

func TestCCRRetrievalTool_Execute_NotFound(t *testing.T) {
	manager, cleanup := setupTestCCRManager(t)
	defer cleanup()

	tool := NewCCRRetrievalTool(manager)
	ctx := context.Background()

	args := map[string]interface{}{
		"hash": "nonexistent00000000000000",
	}
	_, err := tool.Execute(ctx, args)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "failed to retrieve")
}

func TestCCRRetrievalTool_Execute_NoCCRManager(t *testing.T) {
	tool := NewCCRRetrievalTool(nil)
	ctx := context.Background()

	args := map[string]interface{}{
		"hash": "abc123def456789012345678",
	}
	_, err := tool.Execute(ctx, args)
	assert.Error(t, err)
	assert.Contains(t, err.Error(), "CCR manager not configured")
}

func TestCCRRetrievalTool_ToolDefinition(t *testing.T) {
	tool := NewCCRRetrievalTool(nil)
	def := tool.ToolDefinition()

	assert.Equal(t, "headroom_retrieve", def["name"])
	assert.NotEmpty(t, def["description"])
	assert.NotNil(t, def["input_schema"])
}

func TestCCRRetrievalTool_ToolDefinitionAnthropic(t *testing.T) {
	tool := NewCCRRetrievalTool(nil)
	def := tool.ToolDefinitionAnthropic()

	assert.Equal(t, "headroom_retrieve", def["name"])
	assert.NotEmpty(t, def["description"])
	assert.NotNil(t, def["input_schema"])
}

func TestCCRRetrievalTool_ToolDefinitionOpenAI(t *testing.T) {
	tool := NewCCRRetrievalTool(nil)
	def := tool.ToolDefinitionOpenAI()

	assert.Equal(t, "function", def["type"])
	function, ok := def["function"].(map[string]interface{})
	require.True(t, ok)
	assert.Equal(t, "headroom_retrieve", function["name"])
	assert.NotEmpty(t, function["description"])
	assert.NotNil(t, function["parameters"])
}

func TestCCRRetrievalTool_Execute_NonArrayData(t *testing.T) {
	manager, cleanup := setupTestCCRManager(t)
	defer cleanup()

	tool := NewCCRRetrievalTool(manager)
	ctx := context.Background()

	// Store non-array data
	hash := "test123456789012345678ab"
	testData := []byte(`{"key": "value"}`)
	err := manager.Put(ctx, hash, testData, "test_session")
	require.NoError(t, err)

	// Execute retrieval
	args := map[string]interface{}{
		"hash": hash,
	}
	result, err := tool.Execute(ctx, args)
	require.NoError(t, err)
	assert.NotNil(t, result)
}
