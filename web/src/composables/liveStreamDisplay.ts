// liveStreamDisplay — UI helpers for the swim lane.
//
// Trims model names down to the single character that goes on the tile.
// The classifier already maps raw model strings to a canonical family
// (openai / anthropic / domestic / oss / other); we want the family
// letter on the tile so 30+ blocks fit comfortably in one viewport.
//
// Hover/tooltip is built in LiveRequestBlock.vue — this file only
// owns the data-shaping primitives so they can be unit-tested in
// isolation and reused (the legend in LiveStreamLegend.vue uses
// the same letter for consistency).

/**
 * Reduce a model name to a single uppercase letter that fits on a
 * narrow tile. The mapping is family-aware so a wall of mixed
 * traffic still tells you the family at a glance:
 *
 *   gpt-*        → "G"     (openai blue)
 *   claude-*     → "C"     (anthropic purple)
 *   qwen-*       → "Q"     (domestic orange)
 *   glm-*        → "M"     (domestic orange — GLM is the original)
 *   deepseek-*   → "D"
 *   minimax      → "X"     (mapped to model_category=other)
 *   minimax-*    → "X"
 *   llama-*      → "L"
 *   mistral-*    → "M"
 *   default      → "?" for unknown
 *
 * The function is intentionally pure — it is called on every render
 * of every block (up to 50 per second at QPS=50) and must stay cheap.
 */
export function modelGlyph(model: string | undefined | null): string {
  if (!model) return '?'
  const m = model.toLowerCase()
  if (m.startsWith('gpt-') || m.startsWith('o1-') || m.startsWith('o3-') || m.startsWith('o4-')) return 'G'
  if (m.startsWith('claude-')) return 'C'
  if (m.startsWith('qwen')) return 'Q'
  if (m.startsWith('glm-')) return 'M'
  if (m.startsWith('deepseek-')) return 'D'
  if (m.startsWith('moonshot-')) return 'K' // Moonshot → K
  if (m.startsWith('doubao-')) return 'B'   // 豆包 → B
  if (m.startsWith('ernie-')) return 'E'
  if (m.startsWith('llama-') || m.startsWith('llama')) return 'L'
  if (m.startsWith('mistral-') || m.startsWith('mixtral-')) return 'M'
  if (m.startsWith('phi-')) return 'P'
  if (m.startsWith('gemma-')) return 'G'
  if (m.startsWith('minimax')) return 'X'  // minimax → X
  // Fall back to the first alphanumeric char of the raw model name
  const m2 = model.trim()
  if (!m2) return '?'
  const first = m2[0]
  return /[a-zA-Z0-9]/.test(first) ? first.toUpperCase() : '?'
}
