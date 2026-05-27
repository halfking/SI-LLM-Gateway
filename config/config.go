package config

import (
	"os"
	"strings"
)

type Config struct {
	DatabaseURL             string
	SecretKey               string
	CredentialEncryptionKey string
}

func Load() Config {
	return Config{
		DatabaseURL:             firstNonEmpty(os.Getenv("LLM_GATEWAY_DATABASE_URL"), os.Getenv("DATABASE_URL")),
		SecretKey:               firstNonEmpty(os.Getenv("LLM_GATEWAY_SECRET_KEY"), os.Getenv("SECRET_KEY")),
		CredentialEncryptionKey: firstNonEmpty(os.Getenv("LLM_GATEWAY_CREDENTIAL_ENCRYPTION_KEY"), os.Getenv("CREDENTIAL_ENCRYPTION_KEY")),
	}
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
