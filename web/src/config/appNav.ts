/** Sidebar navigation — grouped menus with role / tenant visibility flags. */

export type NavItem = {
  path: string
  /** i18n key for the label, e.g. 'nav.item.tenantModels'. Falls back to `label` if missing. */
  labelKey: string
  /** Hardcoded label kept as a final fallback when the i18n bundle doesn't
   *  contain `labelKey` (e.g. for stub locales). Renders only when the i18n
   *  lookup returns the raw key — see App.vue's `t(item.labelKey ?? item.label)`. */
  label: string
  icon: string
  /** super_admin only */
  super?: boolean
  /** super_admin + default tenant (platform ops) */
  platformOps?: boolean
  /** Non-default tenant portal only */
  tenantOnly?: boolean
  /** Hidden when logged in as non-default tenant (tenant_admin) */
  hideForTenant?: boolean
  /** Only highlight when the path matches exactly (no prefix matching).
   *  Use for items whose path is a prefix of another item's path, e.g.
   *  '/routing-v2' (路由全景) vs '/routing-v2/credentials' (凭据监控) —
   *  without this both highlight at once on the credentials page. */
  exact?: boolean
}

export type NavGroup = {
  id: string
  /** i18n key for the group header, e.g. 'nav.group.tenantPortal'. */
  labelKey: string
  /** Hardcoded fallback when the i18n key is missing. */
  label: string
  items: NavItem[]
}

/** Top-level sidebar links (no accordion group). Used for default-tenant platform ops. */
export const NAV_PRIMARY_ITEMS: NavItem[] = [
  { path: '/', labelKey: 'nav.primary.overview', label: '总览', icon: '📊', platformOps: true },
]

export const NAV_GROUPS: NavGroup[] = [
  {
    id: 'tenant-portal',
    labelKey: 'nav.group.tenantPortal',
    label: '我的服务',
    items: [
      { path: '/tenant/models', labelKey: 'nav.item.tenantModels', label: '标准模型', icon: '🤖', tenantOnly: true },
      { path: '/tenant/account', labelKey: 'nav.item.tenantAccount', label: '我的账户', icon: '💰', tenantOnly: true },
      { path: '/tenant/pricing', labelKey: 'nav.item.tenantPricing', label: '套餐与充值', icon: '💳', tenantOnly: true },
      { path: '/tenant/usage', labelKey: 'nav.item.tenantUsage', label: '我的消耗', icon: '📉', tenantOnly: true },
    ],
  },
  {
    id: 'models-routing',
    labelKey: 'nav.group.modelsRouting',
    label: '模型与路由',
    items: [
      { path: '/models', labelKey: 'nav.item.modelsCatalog', label: '模型与目录', icon: '🏷️', platformOps: true, hideForTenant: true },
      { path: '/routing-v2', labelKey: 'nav.item.routingOverview', label: '路由全景', icon: '🗺️', super: true, hideForTenant: true, exact: true },
      { path: '/routing-v2/credentials', labelKey: 'nav.item.routingCredentials', label: '凭据监控', icon: '📊', super: true, hideForTenant: true },
      { path: '/providers', labelKey: 'nav.item.providers', label: '供应商', icon: '🔌', super: true, hideForTenant: true },
      { path: '/pricing', labelKey: 'nav.item.pricing', label: '成本价格', icon: '📉', platformOps: true, hideForTenant: true },
      { path: '/model-pricing', labelKey: 'nav.item.modelPricing', label: '定价管理', icon: '💰', platformOps: true, hideForTenant: true },
      { path: '/free-pool', labelKey: 'nav.item.freePool', label: '免费资源', icon: '🎁', super: true, hideForTenant: true },
    ],
  },
  {
    id: 'tenant-users',
    labelKey: 'nav.group.tenantUsers',
    label: '租户用户',
    items: [
      { path: '/tenants', labelKey: 'nav.item.tenants', label: '租户管理', icon: '🏢', super: true, hideForTenant: true },
      { path: '/users', labelKey: 'nav.item.users', label: '用户管理', icon: '👤', platformOps: true, hideForTenant: true },
      { path: '/keys', labelKey: 'nav.item.keys', label: 'API 密钥', icon: '🔑' },
      { path: '/key-applications', labelKey: 'nav.item.keyApplications', label: '密钥申请', icon: '📬', super: true, hideForTenant: true },
      { path: '/audit-logs', labelKey: 'nav.item.auditLogs', label: '审计日志', icon: '📋', super: true, hideForTenant: true },
    ],
  },
  {
    id: 'requests-sessions',
    labelKey: 'nav.group.requestsSessions',
    label: '请求与会话',
    items: [
      { path: '/request-logs', labelKey: 'nav.item.requestLogs', label: '请求日志', icon: '📋' },
      { path: '/sessions', labelKey: 'nav.item.sessions', label: '会话列表', icon: '💬' },
      { path: '/session-compare', labelKey: 'nav.item.sessionCompare', label: '会话对比', icon: '🔍' },
      { path: '/admin/compression', labelKey: 'nav.item.compression', label: '压缩概览', icon: '📦', platformOps: true, hideForTenant: true },
      { path: '/session-context', labelKey: 'nav.item.sessionContext', label: '会话上下文', icon: '💭' },
    ],
  },
  {
    id: 'data-ops',
    labelKey: 'nav.group.dataOps',
    label: '数据运维',
    items: [
      { path: '/admin/settings', labelKey: 'nav.item.adminSettings', label: '系统设置', icon: '⚙️', super: true, hideForTenant: true },
      { path: '/admin/data-lifecycle', labelKey: 'nav.item.dataLifecycle', label: '数据生命周期', icon: '💾', platformOps: true, hideForTenant: true },
    ],
  },
  {
    id: 'guide',
    labelKey: 'nav.group.guide',
    label: '接入指南',
    items: [{ path: '/examples', labelKey: 'nav.item.examples', label: '接入示例', icon: '📝' }],
  },
  {
    id: 'chat',
    labelKey: 'nav.group.chat',
    label: '对话',
    items: [{ path: '/chat', labelKey: 'nav.item.chat', label: '对话', icon: '💬' }],
  },
]

export function canShowNavItem(
  item: NavItem,
  opts: { isSuperAdmin: boolean; isPlatformOps: boolean; isTenantPortal: boolean },
): boolean {
  if (item.super && !opts.isSuperAdmin) return false
  if (item.platformOps && !opts.isPlatformOps) return false
  if (item.tenantOnly && !opts.isTenantPortal) return false
  if (item.hideForTenant && opts.isTenantPortal) return false
  return true
}

export function visibleNavItems(
  items: NavItem[],
  opts: { isSuperAdmin: boolean; isPlatformOps: boolean; isTenantPortal: boolean },
): NavItem[] {
  return items.filter((item) => canShowNavItem(item, opts))
}

export function visibleNavGroups(
  groups: NavGroup[],
  opts: { isSuperAdmin: boolean; isPlatformOps: boolean; isTenantPortal: boolean },
): NavGroup[] {
  return groups
    .map((g) => ({
      ...g,
      items: g.items.filter((item) => canShowNavItem(item, opts)),
    }))
    .filter((g) => g.items.length > 0)
}

export function isNavItemActive(path: string, currentPath: string, exact?: boolean): boolean {
  if (path === '/') return currentPath === '/'
  if (exact) return currentPath === path
  return currentPath === path || currentPath.startsWith(path + '/')
}

const SIDEBAR_COLLAPSED_KEY = 'llmgw_sidebar_collapsed'

export function readSidebarCollapsed(): boolean {
  try {
    return localStorage.getItem(SIDEBAR_COLLAPSED_KEY) === '1'
  } catch {
    return false
  }
}

export function writeSidebarCollapsed(collapsed: boolean) {
  try {
    localStorage.setItem(SIDEBAR_COLLAPSED_KEY, collapsed ? '1' : '0')
  } catch {
    // ignore
  }
}
