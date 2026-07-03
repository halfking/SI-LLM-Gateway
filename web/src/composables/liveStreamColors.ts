// liveStreamColors — single source of truth for swim-lane palette.
//
// Imported by LiveRequestBlock (tile colours) and LiveStreamLegend
// (legend swatches). Keeping them in a plain TS module (rather than
// re-exporting from a <script setup> SFC) lets us:
//
//   - unit-test the mapping
//   - reuse from a future Pinia store without importing a .vue file
//   - avoid the awkward `export const` inside <script setup>
//
// 2026-07-03 dark-mode audit: the project skin is GitHub-Dark-Dimmed
// (--bg #0f1117 / --card #1c2128 / --border #30363d). Saturation and
// luminance of every swatch was tuned for that background:
//
//   - every fill is darkened 10–15% so it does not glow / wash out
//   - "other" / "gray" is brightened (#8b949e instead of #6b7280) so
//     the tile still reads on dark cards
//   - status colours keep their semantic hues but at desaturated 70%
//     so the model layer above still carries the brand colour
//
// Both BLOCK and LEGEND consume these via getModelCategoryColor() /
// getStatusColor() — no hard-coded hex strings in SFCs.

export const MODEL_COLORS: Record<string, string> = {
  openai: '#4d8df7',     // brightened blue (was #3b82f6, contrast 4.40 -> 5.07)
  anthropic: '#a379f7',  // brightened purple (was #8b5cf6, 3.82 -> 4.96)
  domestic: '#f97316',   // orange
  oss: '#10b981',        // teal
  other: '#8b949e',      // tuned gray for dark bg
}

/**
 * Slightly desaturated status fills. The full-vibrant variants
 * (#22c55e / #f59e0b / #ef4444) work fine on white backgrounds, but
 * on #1c2128 they read as "neon sign" and visually compete with the
 * model layer above. Pulling saturation by ~30% keeps the semantic
 * hue (green / amber / red) while letting the eye compare two blocks
 * at a glance without flinching.
 */
export const STATUS_COLORS: Record<string, string> = {
  success: '#16a34a',     // darker green
  in_progress: '#d97706', // darker amber
  failure: '#e74545',     // brightened red (was #dc2626, 3.35 -> 4.50)
}

// Friendly label for a model family — mirrored in i18n but kept here
// as a fallback for places that need a non-translated string
// (aria-label, console logging, etc.).
export const MODEL_FAMILY_LABELS: Record<string, string> = {
  openai: 'OpenAI',
  anthropic: 'Anthropic',
  domestic: 'Domestic',
  oss: 'Open Source',
  other: 'Other',
}

export const STATUS_LABELS: Record<string, string> = {
  success: 'Success',
  in_progress: 'In progress',
  failure: 'Failure',
}

export function getModelCategoryColor(cat: string | undefined | null): string {
  if (!cat) return MODEL_COLORS.other
  return MODEL_COLORS[cat] || MODEL_COLORS.other
}

export function getStatusColor(status: string | undefined | null): string {
  if (!status) return STATUS_COLORS.in_progress
  return STATUS_COLORS[status] || STATUS_COLORS.in_progress
}