# How to add a new locale

A runbook for adding a new UI language to the LLM Gateway console.

The console currently ships 8 locales (zh-CN source, en-US reference, zh-TW, ja-JP, de-DE, fr-FR, es-ES, ar-SA). Adding a ninth follows the same seven-step recipe below.

> Time budget: ~30 minutes for the code wiring + a translation pass per module.
> Translation pass per module: ~30–60 min depending on prose density.

---

## Prerequisites

* Node ≥ 18, npm workspace at `web/`.
* Go toolchain (for the backend locale list).
* The new locale's BCP-47 code (e.g. `pt-BR`, `ko-KR`, `ru-RU`).
* A translator (or machine translation pass) for the 31 module files.

---

## Step 1 — Add the locale to `SUPPORTED_LOCALES`

File: `web/src/i18n/constants.ts`

Append a new entry to the array. Keep entries sorted by code (alphabetical).

```ts
{ code: 'pt-BR', short: 'PT', nativeName: 'Português (Brasil)', englishName: 'Portuguese (Brazil)', dir: 'ltr', flag: '🇧🇷' },
```

Fields:

| field         | meaning                                                                                                  |
| ------------- | -------------------------------------------------------------------------------------------------------- |
| `code`        | BCP-47. Also the vue-i18n message key and `toLocaleString` locale.                                       |
| `short`       | 2–3 char label for compact switchers (e.g. "PT").                                                        |
| `nativeName`  | Name written in the locale's own script (for the language menu).                                         |
| `englishName` | English name (for tooling / logs).                                                                       |
| `dir`         | `'ltr'` or `'rtl'`. Set to `'rtl'` for Arabic-style scripts; the i18n runtime sets `<html dir>` for you. |
| `flag`        | Flag emoji.                                                                                              |

> `useLocale.applyDocumentLocale` already consumes `dir` from `SUPPORTED_LOCALES`, so RTL wiring is automatic once you set the field.

---

## Step 2 — Add the locale to the backend's `SupportedLocaleCodes()`

File: `settings/spec_general.go`

```go
func SupportedLocaleCodes() []string {
    return []string{
        "zh-CN",
        "zh-TW",
        "en-US",
        "ja-JP",
        "de-DE",
        "fr-FR",
        "es-ES",
        "ar-SA",
        "pt-BR", // ← add here
    }
}
```

This list backs the `general.default_locale` platform Spec's `Options` array, so admins can pick the new locale from the Settings UI. Re-deploy the Go service after editing this file (hot-reload covers the Spec value but not the option list itself).

---

## Step 3 — Add a `STATIC_LOCALES` or `LAZY_LOADERS` entry

File: `web/src/i18n/index.ts`

Decide whether the locale is **bundled** or **lazy-loaded**:

* **Bundle** (`STATIC_LOCALES`) — recommended for the top-2 languages by traffic. Increases initial chunk size by ~the size of one locale directory.
* **Lazy** (`LAZY_LOADERS`) — recommended for everything else. The locale is fetched on first switch.

```ts
import ptBR from './locales/pt-BR'

const STATIC_LOCALES = {
  'zh-CN': zhCN,
  'en-US': enUS,
  // ... add to STATIC only if this is a tier-1 locale
}

const LAZY_LOADERS: Record<string, () => Promise<{ default: Record<string, unknown> }>> = {
  // ...
  'pt-BR': () => import('./locales/pt-BR'), // ← typical case
}
```

The locale is now reachable from the language switcher.

---

## Step 4 — Create the new locale directory

Directory: `web/src/i18n/locales/<code>/`

Use `en-US/` as the template — copy all 31 module files (`common.ts`, `nav.ts`, …, `correlations.ts`) and translate each.

```bash
cd web/src/i18n/locales
cp -r en-US pt-BR
# then translate each .ts file in-place
```

The 31 module files are:

```
app.ts            dataLifecycle.ts   nav.ts
auditLog.ts       decisions.ts       pricingManagement.ts
chat.ts           errors.ts          providerDetail.ts
common.ts         examples.ts        providerDetailPage.ts
compression.ts    forbidden.ts       providers.ts
correlations.ts   freePool.ts        requests.ts
credentialMonitor.ts  keys.ts        routing.ts
dashboard.ts      landing.ts         sessions.ts
                  login.ts           settings.ts
                  models.ts          standardModelPricing.ts
                  tenants.ts         tuning.ts
                                      users.ts
                                      workTypes.ts
```

> 32 files total (`index.ts` + 31 modules); only the modules need translation.

### Translation rules (codified in `glossary.ts`)

1. **Never translate** any value in `TECH_ACRONYMS` (backend enums, provider codes, role IDs, acronyms). These appear in the UI as-is.
2. **Keep brand names verbatim** (`Kaixuan`, `LLM Gateway`, `MaaS`). See `BRAND_TERMS` for locale-specific spellings.
3. **Universal abbreviations stay verbatim**: `B`, `KB`, `MB`, `GB`, `RPM`, `TPM`, `ms`, `%`.
4. **Translate units** via `UNITS` in `glossary.ts` (`credits`, time units, etc.).
5. Preserve ICU placeholders (`{n}`, `{name}`, `{date}`) and HTML tags.

---

## Step 5 — Wire up the locale's `index.ts`

File: `web/src/i18n/locales/<code>/index.ts`

Mirror the structure of `en-US/index.ts`:

```ts
// pt-BR/index.ts — aggregate Brazilian Portuguese modules.
import common from './common'
import nav from './nav'
// ... one import per module (31 total)

export default {
  common,
  nav,
  // ... one key per module (31 total)
}
```

> Missing imports → empty namespaces in vue-i18n. The parity test (Step 6) catches this.

---

## Step 6 — Run the parity test

The parity test (`scripts/check-i18n-parity.*` or `npm run i18n:parity`) compares the key set of the new locale against `en-US`. It uses `TECH_ACRONYMS` from `glossary.ts` to whitelist values that look English but should stay English.

```bash
cd web
npm run i18n:parity
```

Expected output:

```
✓ pt-BR: key-set matches en-US (243 keys)
✓ pt-BR: 0 missing, 0 extra, 0 unused
```

If the test reports missing keys, you translated a string that should have stayed English (or vice versa) — fix the translation, then re-run.

If the test reports extra keys, you've added strings not present in `en-US`. Either remove them or add the same key to `en-US` (and propagate to all other locales).

---

## Step 7 — Verify RTL handling (if applicable)

If your new locale is RTL (`dir: 'rtl'` in Step 1), verify:

1. **`<html dir="rtl">` is set on first paint.** Already handled by `applyDocumentLocale` — switch to the locale and inspect the document.
2. **Bidirectional isolation for English substrings.** Brand names and enum values inside RTL text need `unicode-bidi: isolate` CSS. See the existing `.ar-SA` styles for the pattern.
3. **Icon mirroring.** Icons that point left/right (arrows, chevrons) need CSS `transform: scaleX(-1)` in RTL contexts. Audit the icons used in modules that show in this locale.
4. **Number formatting.** Verify that `toLocaleString` renders numbers/percentages in the locale's convention (the runtime already passes `meta.code`).

For LTR locales, this step is a no-op.

---

## Validation

```bash
cd web

# Type-check (the glossary file is pure types, must not break tsc)
npx tsc --noEmit 2>&1 | head

# Full build — must succeed
npm run build 2>&1 | rg "built|error" | head

# Parity check
npm run i18n:parity
```

---

## Rollback

If the new locale breaks the build mid-way:

1. Remove the entry from `SUPPORTED_LOCALES` (Step 1).
2. Remove the `STATIC_LOCALES` / `LAZY_LOADERS` entry (Step 3).
3. The locale directory and backend entry can stay (they're inert until re-added).

This restores the previous 8-locale state without touching any other locale files.

---

## See also

* `glossary.ts` — codified brand terms, acronyms, units.
* `constants.ts` — `SUPPORTED_LOCALES`, locale meta helpers.
* `index.ts` — vue-i18n setup, lazy loaders.
* `useLocale.ts` — composable used by the language switcher.
* `settings/spec_general.go` — backend `SupportedLocaleCodes()`.