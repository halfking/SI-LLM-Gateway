// postcss.config.cjs — auto-flip LTR CSS to RTL using postcss-rtlcss.
//
// Why a separate file (rather than embedding in vite.config.ts)?
//   • Vite auto-detects a sibling `postcss.config.{js,cjs,mjs,ts}` for every
//     CSS source (global .css files AND SFC `<style>` blocks via @vitejs/plugin-vue).
//     Keeping it in vite.config.ts under `css.postcss` would also work, but
//     a standalone file is easier for downstream tools (Vitest, stylelint, etc.)
//     to discover.
//
// Why .cjs and not .js?
//   • web/package.json does not declare `"type": "module"`, so a `.js` file
//     would be reparsed as ESM (Node prints a MODULE_TYPELESS_PACKAGE_JSON
//     warning at every Vite start, plus a one-time perf overhead). `.cjs`
//     forces CommonJS unambiguously without touching package.json (the
//     constraint says not to modify package.json).
//
// Mode choice: `combined` (default + recommended).
//   • Output emits base rules plus `[dir="ltr"] …` and `[dir="rtl"] …`
//     prefixed overrides — matches the app's existing `useLocale.ts`
//     which toggles `<html dir="ltr|rtl">` per the active language.
//   • `override` would generate *less* CSS but is explicitly not recommended
//     by the postcss-rtlcss docs (see node_modules/postcss-rtlcss/README.md).
//
// Scope: postcss-rtlcss only processes properties it can deterministically
// mirror (margin-*, padding-*, border-*, left/right, text-align, float,
// background-position, transforms, etc.). It runs in every Vite build
// (dev + prod); the generated CSS file simply contains both branches and
// the browser applies the matching one based on `<html dir>`. There is
// no dev/prod toggle needed and none is exposed by the plugin.
const postcssRTLCSS = require('postcss-rtlcss')

module.exports = {
  plugins: [
    postcssRTLCSS({
      // Generates `[dir="ltr"]` + `[dir="rtl"]` overrides alongside the
      // base rule. Matches the dir toggling done in src/i18n/useLocale.ts.
      mode: 'combined',
    }),
  ],
}