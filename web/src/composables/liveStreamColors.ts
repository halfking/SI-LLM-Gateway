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
//   - status colours (success / failure / in_progress) use semantic
//     green / red / amber tones that remain WCAG AA compliant against
//     both the card and the tile fill
//
// 2026-07-04: Dynamic provider colors - the MODEL_COLORS map is now
// populated dynamically from top providers API instead of hardcoded.

// Default color palette for dynamic provider assignment
export const PROVIDER_COLOR_PALETTE = [
  '#4d8df7', // blue
  '#a379f7', // purple
  '#f97316', // orange
  '#10b981', // green
  '#f59e0b', // amber
  '#ec4899', // pink
  '#06b6d4', // cyan
  '#8b5cf6', // violet
]

// Dynamic model colors - will be populated from API
export const MODEL_COLORS: Record<string, string> = {
  other: '#94a3b8', // gray - fallback for unknown providers
}

// Status colors remain static
export const STATUS_COLORS: Record<string, string> = {
  success: '#10b981',
  in_progress: '#f59e0b',
  failure: '#ef4444',
}

// Alias for backwards compatibility with LiveRequestBlock.vue
export const STATUS_BORDER_COLORS = STATUS_COLORS

export const STATUS_FILL_OPACITY: Record<string, string> = {
  success: '0.12',
  in_progress: '0.08',
  failure: '0.12',
}

// Ring width (stroke-width) — thicker rings give more visual emphasis
export const STATUS_RING_WIDTH: Record<string, string> = {
  success: '2',
  in_progress: '1',
  failure: '2',
  default: '2',
}

// Alias for backwards compatibility with LiveRequestBlock.vue
export const STATUS_BORDER_WIDTHS = STATUS_RING_WIDTH

// Dynamic model family labels - will be populated from API
export const MODEL_FAMILY_LABELS: Record<string, string> = {
  other: 'Other',
}

export const STATUS_LABELS: Record<string, string> = {
  success: 'Success',
  in_progress: 'In progress',
  failure: 'Failure',
}

// Load top providers and update MODEL_COLORS dynamically
export async function loadTopProviders(limit = 6, days = 7): Promise<void> {
  try {
    const response = await fetch(`/api/admin/top-providers?limit=${limit}&days=${days}`, {
      headers: {
        'Authorization': `Bearer ${getAuthToken()}`,
      },
    })
    
    if (!response.ok) {
      console.warn('Failed to load top providers, using fallback colors')
      return
    }

    const data = await response.json()
    const topProviders = data.top_providers || []

    // Clear existing dynamic entries (keep 'other')
    const keysToDelete = Object.keys(MODEL_COLORS).filter(k => k !== 'other')
    keysToDelete.forEach(k => delete MODEL_COLORS[k])
    
    const labelsToDelete = Object.keys(MODEL_FAMILY_LABELS).filter(k => k !== 'other')
    labelsToDelete.forEach(k => delete MODEL_FAMILY_LABELS[k])

    // Populate with top providers
    topProviders.forEach((provider: any, index: number) => {
      const code = provider.provider_code
      const name = provider.provider_name || code
      const color = provider.color || PROVIDER_COLOR_PALETTE[index % PROVIDER_COLOR_PALETTE.length]
      
      MODEL_COLORS[code] = color
      MODEL_FAMILY_LABELS[code] = name
    })
  } catch (error) {
    console.error('Error loading top providers:', error)
  }
}

// Helper to get auth token from localStorage or cookie
function getAuthToken(): string {
  // Try localStorage first
  const token = localStorage.getItem('auth_token') || sessionStorage.getItem('auth_token')
  if (token) return token

  // Fallback to cookie
  const cookies = document.cookie.split(';')
  for (const cookie of cookies) {
    const [name, value] = cookie.trim().split('=')
    if (name === 'auth_token' || name === 'jwt_token') {
      return value
    }
  }
  
  return ''
}

export function getModelCategoryColor(cat: string | undefined | null): string {
  if (!cat) return MODEL_COLORS.other
  return MODEL_COLORS[cat] || MODEL_COLORS.other
}

export function getStatusColor(status: string | undefined | null): string {
  if (!status) return STATUS_COLORS.in_progress
  return STATUS_COLORS[status] || STATUS_COLORS.in_progress
}
