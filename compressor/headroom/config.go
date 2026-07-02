package headroom

import (
	"os"
	"strconv"
	"time"
)

// Config provides runtime configuration for Headroom compression.
type Config struct {
	// Enabled controls whether Headroom compression is active
	Enabled bool

	// MaxItemsAfterCrush is the maximum items to keep after compression
	MaxItemsAfterCrush int

	// MinItemsToAnalyze is the minimum array size to consider
	MinItemsToAnalyze int

	// LosslessMinSavingsRatio is the minimum savings for lossless compression
	LosslessMinSavingsRatio float64

	// Bias adjusts the adaptive k-value (>1 keeps more, <1 compresses more)
	Bias float64

	// EnableCCRMarker controls CCR marker injection
	EnableCCRMarker bool

	// LosslessOnly skips lossy compression
	LosslessOnly bool

	// CCRL1MaxItems is the L1 cache size
	CCRL1MaxItems int64

	// CCRL2TTL is the Redis TTL duration
	CCRL2TTL time.Duration

	// Timeout is the max time for compression operation
	Timeout time.Duration
}

// LoadConfigFromEnv loads Headroom configuration from environment variables.
func LoadConfigFromEnv() Config {
	return Config{
		Enabled:                 getEnvBool("LLM_GATEWAY_HEADROOM_ENABLED", true),
		MaxItemsAfterCrush:      getEnvInt("LLM_GATEWAY_HEADROOM_MAX_ITEMS", 15),
		MinItemsToAnalyze:       getEnvInt("LLM_GATEWAY_HEADROOM_MIN_ITEMS", 5),
		LosslessMinSavingsRatio: getEnvFloat("LLM_GATEWAY_HEADROOM_MIN_SAVINGS_RATIO", 0.30),
		Bias:                    getEnvFloat("LLM_GATEWAY_HEADROOM_BIAS", 1.0),
		EnableCCRMarker:         getEnvBool("LLM_GATEWAY_HEADROOM_CCR_MARKER", true),
		LosslessOnly:            getEnvBool("LLM_GATEWAY_HEADROOM_LOSSLESS_ONLY", false),
		CCRL1MaxItems:           int64(getEnvInt("LLM_GATEWAY_CCR_L1_SIZE", 1000)),
		CCRL2TTL:                getEnvDuration("LLM_GATEWAY_CCR_L2_TTL", 24*time.Hour),
		Timeout:                 getEnvDuration("LLM_GATEWAY_HEADROOM_TIMEOUT", 50*time.Millisecond),
	}
}

// ToSmartCrusherConfig converts to SmartCrusherConfig.
func (c Config) ToSmartCrusherConfig() SmartCrusherConfig {
	return SmartCrusherConfig{
		MaxItemsAfterCrush:      c.MaxItemsAfterCrush,
		MinItemsToAnalyze:       c.MinItemsToAnalyze,
		LosslessMinSavingsRatio: c.LosslessMinSavingsRatio,
		FactorOutConstants:      true,
		EnableCCRMarker:         c.EnableCCRMarker,
		LosslessOnly:            c.LosslessOnly,
		Bias:                    c.Bias,
	}
}

// getEnvBool reads a boolean environment variable.
func getEnvBool(key string, defaultVal bool) bool {
	val := os.Getenv(key)
	if val == "" {
		return defaultVal
	}
	b, err := strconv.ParseBool(val)
	if err != nil {
		return defaultVal
	}
	return b
}

// getEnvInt reads an integer environment variable.
func getEnvInt(key string, defaultVal int) int {
	val := os.Getenv(key)
	if val == "" {
		return defaultVal
	}
	i, err := strconv.Atoi(val)
	if err != nil {
		return defaultVal
	}
	return i
}

// getEnvFloat reads a float environment variable.
func getEnvFloat(key string, defaultVal float64) float64 {
	val := os.Getenv(key)
	if val == "" {
		return defaultVal
	}
	f, err := strconv.ParseFloat(val, 64)
	if err != nil {
		return defaultVal
	}
	return f
}

// getEnvDuration reads a duration environment variable.
func getEnvDuration(key string, defaultVal time.Duration) time.Duration {
	val := os.Getenv(key)
	if val == "" {
		return defaultVal
	}
	d, err := time.ParseDuration(val)
	if err != nil {
		return defaultVal
	}
	return d
}
