import { describe, expect, it } from 'vitest'
import { NAV_GROUPS } from './appNav'

describe('opsplatform nav → maintain SPA', () => {
  const opsGroup = NAV_GROUPS.find((g) => g.id === 'opsplatform')!

  it('exposes an opsplatform group', () => {
    expect(opsGroup).toBeTruthy()
  })

  it('marks migrated ops items as external /maintain/* links', () => {
    const external = opsGroup.items.filter((i) => i.external)
    expect(external.length).toBeGreaterThanOrEqual(7)
    for (const item of external) {
      expect(item.path.startsWith('/maintain/')).toBe(true)
    }
  })

  it('keeps vibecoding inside the Gateway SPA', () => {
    const vibe = opsGroup.items.find((i) => i.path === '/ops/vibecoding')
    expect(vibe).toBeTruthy()
    expect(vibe!.external).toBeFalsy()
  })

  it('includes product entry and ops overview external entries', () => {
    const paths = opsGroup.items.map((i) => i.path)
    expect(paths).toContain('/maintain/ops/overview')
    expect(paths).toContain('/maintain/download')
    expect(paths).toContain('/maintain/ops/downloads')
  })
})
