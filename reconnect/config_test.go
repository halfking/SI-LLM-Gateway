package reconnect

import (
	"testing"
)

func TestConfig_IsEnabledForTenant(t *testing.T) {
	cfg := NewConfig()
	cfg.Enabled = true

	// Global enabled, no override
	if !cfg.IsEnabledForTenant("default") {
		t.Error("expected enabled for default tenant")
	}

	// Tenant override: disabled
	cfg.SetTenantConfig("tenant-a", &TenantConfig{Enabled: false})
	if cfg.IsEnabledForTenant("tenant-a") {
		t.Error("expected disabled for tenant-a due to override")
	}

	// Tenant override: enabled
	cfg.SetTenantConfig("tenant-b", &TenantConfig{Enabled: true})
	if !cfg.IsEnabledForTenant("tenant-b") {
		t.Error("expected enabled for tenant-b due to override")
	}
}

func TestConfig_IsEnabledForTenant_GlobalDisabled(t *testing.T) {
	cfg := NewConfig()
	cfg.Enabled = false

	// Global disabled, no override
	if cfg.IsEnabledForTenant("default") {
		t.Error("expected disabled when global is disabled")
	}

	// Global disabled overrides tenant config
	cfg.SetTenantConfig("tenant-a", &TenantConfig{Enabled: true})
	if cfg.IsEnabledForTenant("tenant-a") {
		t.Error("expected disabled when global is disabled (even with tenant override)")
	}
}

func TestConfig_ShouldAutoResume(t *testing.T) {
	cfg := NewConfig()
	cfg.Enabled = true
	cfg.AutoResumeByDefault = false

	// Global default: no auto-resume
	if cfg.ShouldAutoResume("default") {
		t.Error("expected no auto-resume by default")
	}

	// Tenant override: auto-resume enabled
	cfg.SetTenantConfig("tenant-a", &TenantConfig{
		Enabled:             true,
		AutoResumeByDefault: true,
	})
	if !cfg.ShouldAutoResume("tenant-a") {
		t.Error("expected auto-resume for tenant-a due to override")
	}

	// Global auto-resume enabled
	cfg.AutoResumeByDefault = true
	if !cfg.ShouldAutoResume("default") {
		t.Error("expected auto-resume when global default is true")
	}
}

func TestConfig_ShouldAutoResume_DisabledTenant(t *testing.T) {
	cfg := NewConfig()
	cfg.Enabled = true
	cfg.AutoResumeByDefault = true

	// Tenant disabled: no auto-resume even if global is true
	cfg.SetTenantConfig("tenant-a", &TenantConfig{
		Enabled:             false,
		AutoResumeByDefault: true,
	})
	if cfg.ShouldAutoResume("tenant-a") {
		t.Error("expected no auto-resume when tenant is disabled")
	}
}

func TestConfig_SetTenantConfig_Remove(t *testing.T) {
	cfg := NewConfig()
	cfg.Enabled = true

	cfg.SetTenantConfig("tenant-a", &TenantConfig{Enabled: false})
	if cfg.IsEnabledForTenant("tenant-a") {
		t.Error("expected disabled for tenant-a")
	}

	// Remove override
	cfg.SetTenantConfig("tenant-a", nil)
	if !cfg.IsEnabledForTenant("tenant-a") {
		t.Error("expected enabled for tenant-a after removing override")
	}
}

func TestManager_UpdateGlobal(t *testing.T) {
	mgr := NewManager(nil, nil)
	initialCfg := mgr.GetConfig()
	if initialCfg.Enabled {
		t.Error("expected default config to be disabled")
	}

	mgr.UpdateGlobal(true, true)
	updatedCfg := mgr.GetConfig()
	if !updatedCfg.Enabled {
		t.Error("expected enabled after UpdateGlobal")
	}
	if !updatedCfg.AutoResumeByDefault {
		t.Error("expected auto-resume enabled after UpdateGlobal")
	}
}

func TestManager_UpdateTenant(t *testing.T) {
	mgr := NewManager(nil, nil)
	mgr.UpdateGlobal(true, false)

	mgr.UpdateTenant("tenant-x", &TenantConfig{
		Enabled:             true,
		AutoResumeByDefault: true,
	})

	cfg := mgr.GetConfig()
	if !cfg.ShouldAutoResume("tenant-x") {
		t.Error("expected auto-resume for tenant-x after UpdateTenant")
	}

	// Remove tenant config
	mgr.UpdateTenant("tenant-x", nil)
	if cfg.ShouldAutoResume("tenant-x") {
		t.Error("expected no auto-resume for tenant-x after removing config")
	}
}

func TestNewConfig_Defaults(t *testing.T) {
	cfg := NewConfig()
	if cfg.Enabled {
		t.Error("expected default config to be disabled (opt-in)")
	}
	if cfg.AutoResumeByDefault {
		t.Error("expected default auto-resume to be false")
	}
	if cfg.TenantOverrides == nil {
		t.Error("expected TenantOverrides map to be initialized")
	}
}
