package settings

// spec_general.go — General/platform-wide settings.
// 2026-07-02: Added general.default_locale for i18n platform default language.
// New users / clients that have not chosen a UI locale fall back to this value.
// An authenticated user's own locale preference (stored client-side) overrides it.

// SupportedLocaleCodes is the canonical list of UI locales supported by the
// web console. Keep in sync with web/src/i18n/constants.ts SUPPORTED_LOCALES.
func SupportedLocaleCodes() []string {
	return []string{
		"zh-CN", // 简体中文
		"zh-TW", // 繁體中文
		"en-US", // English
		"ja-JP", // 日本語
		"de-DE", // Deutsch
		"fr-FR", // Français
		"es-ES", // Español
		"ar-SA", // العربية (RTL)
	}
}

// GeneralSpecs returns platform-wide "general" category specs.
func GeneralSpecs() []*Spec {
	return []*Spec{
		{
			Key:      "general.default_locale",
			EnvName:  "LLM_GATEWAY_DEFAULT_LOCALE",
			Type:     TypeEnum, // TypeEnum so Options are validated; TypeString ignores Options.
			Scope:    ScopePlatform,
			Category: CategoryGeneral,
			Default:  "zh-CN",
			Options:  SupportedLocaleCodes(),
			Description:     "平台默认语言",
			DescriptionLong: "新用户/未设置语言偏好的客户端使用的默认 UI 语言。" +
				"已登录用户自身的语言偏好优先于此设置。" +
				"修改后立即生效（热重载）。",
			DangerLevel:   Safe,
			HotReload:     true,
			Observability: "/api/admin/settings/general.default_locale",
		},
	}
}
