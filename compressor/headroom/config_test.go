package headroom

import (
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
)

func TestLoadConfigFromEnv_Defaults(t *testing.T) {
	// Clear environment
	os.Clearenv()

	config := LoadConfigFromEnv()

	assert.True(t, config.Enabled)
	assert.Equal(t, 15, config.MaxItemsAfterCrush)
	assert.Equal(t, 5, config.MinItemsToAnalyze)
	assert.Equal(t, 0.30, config.LosslessMinSavingsRatio)
	assert.Equal(t, 1.0, config.Bias)
	assert.True(t, config.EnableCCRMarker)
	assert.False(t, config.LosslessOnly)
	assert.Equal(t, int64(1000), config.CCRL1MaxItems)
	assert.Equal(t, 24*time.Hour, config.CCRL2TTL)
	assert.Equal(t, 50*time.Millisecond, config.Timeout)
}

func TestLoadConfigFromEnv_CustomValues(t *testing.T) {
	// Set custom environment variables
	os.Setenv("LLM_GATEWAY_HEADROOM_ENABLED", "false")
	os.Setenv("LLM_GATEWAY_HEADROOM_MAX_ITEMS", "20")
	os.Setenv("LLM_GATEWAY_HEADROOM_MIN_ITEMS", "10")
	os.Setenv("LLM_GATEWAY_HEADROOM_MIN_SAVINGS_RATIO", "0.5")
	os.Setenv("LLM_GATEWAY_HEADROOM_BIAS", "1.5")
	os.Setenv("LLM_GATEWAY_HEADROOM_CCR_MARKER", "false")
	os.Setenv("LLM_GATEWAY_HEADROOM_LOSSLESS_ONLY", "true")
	os.Setenv("LLM_GATEWAY_CCR_L1_SIZE", "2000")
	os.Setenv("LLM_GATEWAY_CCR_L2_TTL", "48h")
	os.Setenv("LLM_GATEWAY_HEADROOM_TIMEOUT", "100ms")
	defer os.Clearenv()

	config := LoadConfigFromEnv()

	assert.False(t, config.Enabled)
	assert.Equal(t, 20, config.MaxItemsAfterCrush)
	assert.Equal(t, 10, config.MinItemsToAnalyze)
	assert.Equal(t, 0.5, config.LosslessMinSavingsRatio)
	assert.Equal(t, 1.5, config.Bias)
	assert.False(t, config.EnableCCRMarker)
	assert.True(t, config.LosslessOnly)
	assert.Equal(t, int64(2000), config.CCRL1MaxItems)
	assert.Equal(t, 48*time.Hour, config.CCRL2TTL)
	assert.Equal(t, 100*time.Millisecond, config.Timeout)
}

func TestConfig_ToSmartCrusherConfig(t *testing.T) {
	config := Config{
		MaxItemsAfterCrush:      20,
		MinItemsToAnalyze:       10,
		LosslessMinSavingsRatio: 0.4,
		Bias:                    1.2,
		EnableCCRMarker:         false,
		LosslessOnly:            true,
	}

	scConfig := config.ToSmartCrusherConfig()

	assert.Equal(t, 20, scConfig.MaxItemsAfterCrush)
	assert.Equal(t, 10, scConfig.MinItemsToAnalyze)
	assert.Equal(t, 0.4, scConfig.LosslessMinSavingsRatio)
	assert.Equal(t, 1.2, scConfig.Bias)
	assert.False(t, scConfig.EnableCCRMarker)
	assert.True(t, scConfig.LosslessOnly)
	assert.True(t, scConfig.FactorOutConstants)
}

func TestGetEnvBool(t *testing.T) {
	tests := []struct {
		name       string
		envVal     string
		defaultVal bool
		want       bool
	}{
		{"empty uses default true", "", true, true},
		{"empty uses default false", "", false, false},
		{"true", "true", false, true},
		{"false", "false", true, false},
		{"1", "1", false, true},
		{"0", "0", true, false},
		{"invalid uses default", "invalid", true, true},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			key := "TEST_BOOL_KEY"
			if tt.envVal != "" {
				os.Setenv(key, tt.envVal)
				defer os.Unsetenv(key)
			}
			got := getEnvBool(key, tt.defaultVal)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetEnvInt(t *testing.T) {
	tests := []struct {
		name       string
		envVal     string
		defaultVal int
		want       int
	}{
		{"empty uses default", "", 42, 42},
		{"valid int", "100", 42, 100},
		{"negative", "-5", 42, -5},
		{"invalid uses default", "abc", 42, 42},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			key := "TEST_INT_KEY"
			if tt.envVal != "" {
				os.Setenv(key, tt.envVal)
				defer os.Unsetenv(key)
			}
			got := getEnvInt(key, tt.defaultVal)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetEnvFloat(t *testing.T) {
	tests := []struct {
		name       string
		envVal     string
		defaultVal float64
		want       float64
	}{
		{"empty uses default", "", 0.5, 0.5},
		{"valid float", "0.75", 0.5, 0.75},
		{"negative", "-1.5", 0.5, -1.5},
		{"invalid uses default", "abc", 0.5, 0.5},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			key := "TEST_FLOAT_KEY"
			if tt.envVal != "" {
				os.Setenv(key, tt.envVal)
				defer os.Unsetenv(key)
			}
			got := getEnvFloat(key, tt.defaultVal)
			assert.Equal(t, tt.want, got)
		})
	}
}

func TestGetEnvDuration(t *testing.T) {
	tests := []struct {
		name       string
		envVal     string
		defaultVal time.Duration
		want       time.Duration
	}{
		{"empty uses default", "", time.Second, time.Second},
		{"valid duration", "5s", time.Second, 5 * time.Second},
		{"milliseconds", "100ms", time.Second, 100 * time.Millisecond},
		{"hours", "2h", time.Second, 2 * time.Hour},
		{"invalid uses default", "abc", time.Second, time.Second},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			key := "TEST_DURATION_KEY"
			if tt.envVal != "" {
				os.Setenv(key, tt.envVal)
				defer os.Unsetenv(key)
			}
			got := getEnvDuration(key, tt.defaultVal)
			assert.Equal(t, tt.want, got)
		})
	}
}
