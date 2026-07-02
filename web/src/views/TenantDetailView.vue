<script setup lang="ts">
import { ref, computed, onMounted, watch } from 'vue'
import { useRoute, useRouter, RouterLink } from 'vue-router'
import { useI18n } from 'vue-i18n'
import {
  getTenant, getTenantUsers, getTenantKeys, getTenantStats, updateUser,
  getAdminMaasWallet, getAdminMaasLedger, adjustAdminMaasCredits, grantAdminMaasCredits,
  getAdminMaasTenantOrders, confirmAdminMaasOrder,
  MAAS_LEDGER_TYPE_LABELS, MAAS_POOL_LABELS, MAAS_ORDER_STATUS_LABELS,
  TENANT_STATUS_LABELS, TENANT_STATUS_COLORS,
} from '../api'
import type { Tenant, TenantUser, TenantKey, TenantStats, MaasWallet, MaasLedgerEntry, MaasBillingOrder } from '../api'
import TenantEditDialog from './TenantEditDialog.vue'
import FeeCostCell from '../components/FeeCostCell.vue'
import TenantModelPolicyPanel from '../components/TenantModelPolicyPanel.vue'
import { isPlatformOpsView } from '../store'
import { useFormat } from '../i18n/useFormat'

const route = useRoute()
const router = useRouter()
const tenantCode = computed(() => String(route.params.tenantId))
const { t: td } = useI18n()
const tt = (k: string, params?: Record<string, unknown>): string => td(`tenants.detail.${k}` as never, params as never)
const { fmtDateTime, fmtNumber } = useFormat()

const tenant = ref<Tenant | null>(null)
const users = ref<TenantUser[]>([])
const keys = ref<TenantKey[]>([])
const stats = ref<TenantStats | null>(null)
const loading = ref(false)
const error = ref('')
const activeTab = ref<'overview' | 'users' | 'keys' | 'stats' | 'wallet' | 'ledger' | 'orders' | 'model-policies'>('overview')
const statsDays = ref(7)
const showEdit = ref(false)
const maasWallet = ref<MaasWallet | null>(null)
const maasLedger = ref<MaasLedgerEntry[]>([])
const maasOrders = ref<MaasBillingOrder[]>([])
const adjustAmount = ref('')
const adjustNote = ref('')
const grantAmount = ref('')
const grantNote = ref('')
const adjustSaving = ref(false)
const grantSaving = ref(false)
const confirmSaving = ref<number | null>(null)
const showCost = isPlatformOpsView()

async function loadTenant() {
  loading.value = true
  error.value = ''
  try {
    tenant.value = await getTenant(tenantCode.value)
    if (activeTab.value === 'users') await loadUsers()
    if (activeTab.value === 'keys') await loadKeys()
    if (activeTab.value === 'stats') await loadStats()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadFailed')
  } finally {
    loading.value = false
  }
}

async function loadUsers() {
  try {
    users.value = await getTenantUsers(tenantCode.value)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadUsersFailed')
  }
}

async function loadKeys() {
  try {
    keys.value = await getTenantKeys(tenantCode.value)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadKeysFailed')
  }
}

async function loadStats() {
  try {
    stats.value = await getTenantStats(tenantCode.value, statsDays.value)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadStatsFailed')
  }
}

async function loadWallet() {
  try {
    maasWallet.value = await getAdminMaasWallet(tenantCode.value)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadWalletFailed')
  }
}

async function loadLedger() {
  try {
    const res = await getAdminMaasLedger(tenantCode.value, 100)
    maasLedger.value = res.items ?? []
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadLedgerFailed')
  }
}

async function loadOrders() {
  try {
    const res = await getAdminMaasTenantOrders(tenantCode.value, 50)
    maasOrders.value = res.items ?? []
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadOrdersFailed')
  }
}

async function submitAdjust() {
  const amount = parseInt(adjustAmount.value, 10)
  if (!amount || Number.isNaN(amount)) {
    error.value = tt('adjustMissing')
    return
  }
  adjustSaving.value = true
  error.value = ''
  try {
    await adjustAdminMaasCredits(tenantCode.value, amount, adjustNote.value.trim())
    adjustAmount.value = ''
    adjustNote.value = ''
    await Promise.all([loadWallet(), loadLedger()])
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('adjustFailed')
  } finally {
    adjustSaving.value = false
  }
}

async function submitGrant() {
  const amount = parseInt(grantAmount.value, 10)
  if (!amount || Number.isNaN(amount) || amount <= 0) {
    error.value = tt('grantMissing')
    return
  }
  grantSaving.value = true
  error.value = ''
  try {
    await grantAdminMaasCredits(tenantCode.value, amount, grantNote.value.trim())
    grantAmount.value = ''
    grantNote.value = ''
    await Promise.all([loadWallet(), loadLedger()])
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('grantFailed')
  } finally {
    grantSaving.value = false
  }
}

async function confirmOrder(orderId: number) {
  confirmSaving.value = orderId
  error.value = ''
  try {
    await confirmAdminMaasOrder(orderId, '管理员手动确认到账')
    await Promise.all([loadOrders(), loadWallet(), loadLedger()])
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('confirmOrderFailed')
  } finally {
    confirmSaving.value = null
  }
}

function poolLabel(p: string | null | undefined) {
  if (!p) return '—'
  return MAAS_POOL_LABELS[p] || p
}

function orderStatusLabel(s: string) {
  return MAAS_ORDER_STATUS_LABELS[s] || s
}

function fmtPrice(cents: number) {
  return (cents / 100).toFixed(2)
}

function fmtCredits(n: number) {
  const sign = n > 0 ? '+' : ''
  return sign + fmtNumber(n)
}

function ledgerTypeLabel(t: string) {
  return MAAS_LEDGER_TYPE_LABELS[t] || t
}

async function switchTab(t: 'overview' | 'users' | 'keys' | 'stats' | 'wallet' | 'ledger' | 'orders' | 'model-policies') {
  activeTab.value = t
  if (t === 'users' && users.value.length === 0) await loadUsers()
  if (t === 'keys' && keys.value.length === 0) await loadKeys()
  if (t === 'stats' && !stats.value) await loadStats()
  if (t === 'wallet' && !maasWallet.value) await loadWallet()
  if (t === 'ledger' && maasLedger.value.length === 0) await loadLedger()
  if (t === 'orders' && maasOrders.value.length === 0) await loadOrders()
}

async function toggleUserEnabled(u: TenantUser) {
  try {
    await updateUser(u.id, { enabled: !u.enabled })
    await loadUsers()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('operationFailed')
  }
}

function openEdit() {
  showEdit.value = true
}

function statusColor(s: string) {
  return TENANT_STATUS_COLORS[s] || 'badge-gray'
}

function statusLabel(s: string) {
  return TENANT_STATUS_LABELS[s] || s
}

function maasLink(path: string) {
  return { path, query: { tenant: tenantCode.value } }
}

onMounted(loadTenant)
watch(() => route.params.tenantId, loadTenant)
</script>

<template>
  <div class="tenant-detail">
    <div v-if="error" class="alert alert-danger" style="margin-bottom:12px">{{ error }}</div>

    <div v-if="loading && !tenant" class="loading">{{ tt('loading') }}</div>

    <div v-else-if="tenant">
      <!-- Header -->
      <div class="tenant-header">
        <button class="btn-back" @click="router.push('/tenants')">{{ tt('backToList') }}</button>
        <div class="header-main">
          <h1>
            <strong>{{ tenant.name }}</strong>
            <span class="badge" :class="statusColor(tenant.status)">{{ statusLabel(tenant.status) }}</span>
          </h1>
          <div class="header-meta">
            <code class="code-badge">{{ tenant.code }}</code>
            <span v-if="tenant.contact_email">📧 {{ tenant.contact_email }}</span>
            <span>🕐 {{ fmtDateTime(tenant.created_at) }}</span>
          </div>
          <p v-if="tenant.description" class="description">{{ tenant.description }}</p>
        </div>
        <button class="btn btn-primary" @click="openEdit">{{ tt('edit') }}</button>
      </div>

      <!-- Tabs -->
      <div class="tabs">
        <button :class="{ active: activeTab === 'overview' }" @click="switchTab('overview')">{{ tt('tabOverview') }}</button>
        <button :class="{ active: activeTab === 'users' }" @click="switchTab('users')">{{ tt('tabUsers', { n: tenant.user_count }) }}</button>
        <button :class="{ active: activeTab === 'keys' }" @click="switchTab('keys')">{{ tt('tabKeys', { n: tenant.api_key_count }) }}</button>
        <button :class="{ active: activeTab === 'model-policies' }" @click="switchTab('model-policies')">{{ tt('tabModelPolicies') }}</button>
        <button :class="{ active: activeTab === 'stats' }" @click="switchTab('stats')">{{ tt('tabStats') }}</button>
        <button :class="{ active: activeTab === 'wallet' }" @click="switchTab('wallet')">{{ tt('tabWallet') }}</button>
        <button :class="{ active: activeTab === 'orders' }" @click="switchTab('orders')">{{ tt('tabOrders') }}</button>
        <button :class="{ active: activeTab === 'ledger' }" @click="switchTab('ledger')">{{ tt('tabLedger') }}</button>
      </div>

      <!-- Overview Tab -->
      <div v-if="activeTab === 'overview'" class="tab-content">
        <div class="stat-cards">
          <div class="stat-card">
            <div class="stat-label">{{ tt('overviewStat.users') }}</div>
            <div class="stat-value">{{ tenant.user_count }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('overviewStat.keys') }}</div>
            <div class="stat-value">{{ tenant.api_key_count }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('overviewStat.requests7d') }}</div>
            <div class="stat-value">{{ fmtNumber(tenant.requests_7d ?? 0) }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('overviewStat.tokens7d') }}</div>
            <div class="stat-value">{{ fmtNumber(tenant.tokens_7d ?? 0) }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('overviewStat.cost7d') }}</div>
            <div class="stat-value stat-value--fee">
              <FeeCostCell
                inline
                :credits="tenant.credits_7d"
                :cost-usd="tenant.cost_7d_usd"
                :show-cost="showCost"
              />
            </div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('overviewStat.totalRequests') }}</div>
            <div class="stat-value">{{ fmtNumber(tenant.total_requests ?? 0) }}</div>
          </div>
        </div>

        <div class="maas-shortcuts">
          <h3>{{ tt('maasTitle') }}</h3>
          <p class="maas-shortcuts-desc">{{ tt('maasDesc') }}</p>
          <div class="maas-shortcut-grid">
            <RouterLink :to="maasLink('/tenant/models')" class="maas-shortcut-card">
              <span class="maas-shortcut-icon">🤖</span>
              <span class="maas-shortcut-label">{{ tt('maasStandardModels') }}</span>
            </RouterLink>
            <RouterLink :to="maasLink('/tenant/pricing')" class="maas-shortcut-card">
              <span class="maas-shortcut-icon">💳</span>
              <span class="maas-shortcut-label">{{ tt('maasPricing') }}</span>
            </RouterLink>
            <RouterLink :to="maasLink('/tenant/usage')" class="maas-shortcut-card">
              <span class="maas-shortcut-icon">📉</span>
              <span class="maas-shortcut-label">{{ tt('maasUsage') }}</span>
            </RouterLink>
            <RouterLink :to="maasLink('/tenant/account')" class="maas-shortcut-card">
              <span class="maas-shortcut-icon">💰</span>
              <span class="maas-shortcut-label">{{ tt('maasAccount') }}</span>
            </RouterLink>
            <button type="button" class="maas-shortcut-card maas-shortcut-card--tab" @click="switchTab('wallet')">
              <span class="maas-shortcut-icon">👛</span>
              <span class="maas-shortcut-label">{{ tt('maasWallet') }}</span>
            </button>
            <button type="button" class="maas-shortcut-card maas-shortcut-card--tab" @click="switchTab('ledger')">
              <span class="maas-shortcut-icon">📒</span>
              <span class="maas-shortcut-label">{{ tt('maasLedger') }}</span>
            </button>
          </div>
        </div>
      </div>

      <!-- Users Tab -->
      <div v-if="activeTab === 'users'" class="tab-content">
        <table class="table" style="width:100%">
          <thead>
            <tr>
              <th>{{ tt('users.colId') }}</th>
              <th>{{ tt('users.colUsername') }}</th>
              <th>{{ tt('users.colDisplayName') }}</th>
              <th>{{ tt('users.colEmail') }}</th>
              <th>{{ tt('users.colRole') }}</th>
              <th>{{ tt('users.colStatus') }}</th>
              <th>{{ tt('users.colLastLogin') }}</th>
              <th>{{ tt('users.colActions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="u in users" :key="u.id">
              <td>{{ u.id }}</td>
              <td><strong>{{ u.username }}</strong></td>
              <td>{{ u.display_name || '-' }}</td>
              <td>{{ u.email || '-' }}</td>
              <td><span class="badge" :class="u.role === 'super_admin' ? 'badge-purple' : 'badge-blue'">{{ u.role }}</span></td>
              <td><span class="badge" :class="u.enabled ? 'badge-green' : 'badge-red'">{{ u.enabled ? tt('users.enable') : tt('users.disable') }}</span></td>
              <td class="mono">{{ fmtDateTime(u.last_login_at || '') }}</td>
              <td>
                <button class="btn btn-ghost btn-sm" @click="toggleUserEnabled(u)">
                  {{ u.enabled ? tt('users.disable') : tt('users.enable') }}
                </button>
              </td>
            </tr>
            <tr v-if="users.length === 0">
              <td colspan="8" style="text-align:center; padding:40px; color: var(--muted)">{{ tt('users.empty') }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Keys Tab -->
      <div v-if="activeTab === 'keys'" class="tab-content">
        <table class="table" style="width:100%">
          <thead>
            <tr>
              <th>{{ tt('keys.colId') }}</th>
              <th>{{ tt('keys.colPrefix') }}</th>
              <th>{{ tt('keys.colAlias') }}</th>
              <th>{{ tt('keys.colApp') }}</th>
              <th>{{ tt('keys.colStatus') }}</th>
              <th>{{ tt('keys.colRequests') }}</th>
              <th>{{ tt('keys.colCost') }}</th>
              <th>{{ tt('keys.colCreated') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="k in keys" :key="k.id">
              <td>{{ k.id }}</td>
              <td><code>{{ k.key_prefix }}</code></td>
              <td>{{ k.key_alias || '-' }}</td>
              <td><span class="badge badge-blue">{{ k.application_code || '-' }}</span></td>
              <td><span class="badge" :class="k.enabled ? 'badge-green' : 'badge-red'">{{ k.enabled ? tt('keys.enable') : tt('keys.disable') }}</span></td>
              <td>{{ fmtNumber(k.total_requests) }}</td>
              <td>
                <span v-if="showCost">${{ (k.total_cost_usd ?? 0).toFixed(2) }}</span>
                <span v-else>—</span>
              </td>
              <td class="mono">{{ fmtDateTime(k.created_at) }}</td>
            </tr>
            <tr v-if="keys.length === 0">
              <td colspan="8" style="text-align:center; padding:40px; color: var(--muted)">{{ tt('keys.empty') }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Model Policies Tab -->
      <div v-if="activeTab === 'model-policies'" class="tab-content">
        <TenantModelPolicyPanel :tenant-code="tenant.code" />
      </div>

      <!-- Stats Tab -->
      <div v-if="activeTab === 'stats'" class="tab-content">
        <div class="stats-toolbar">
          <label>{{ tt('stats.windowLabel') }}</label>
          <select v-model.number="statsDays" @change="loadStats">
            <option :value="7">{{ tt('stats.window7') }}</option>
            <option :value="30">{{ tt('stats.window30') }}</option>
            <option :value="90">{{ tt('stats.window90') }}</option>
            <option :value="365">{{ tt('stats.window365') }}</option>
          </select>
        </div>

        <div v-if="stats" class="stat-cards">
          <div class="stat-card">
            <div class="stat-label">{{ tt('stats.totalRequests') }}</div>
            <div class="stat-value">{{ fmtNumber(stats.total_requests) }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('stats.totalTokens') }}</div>
            <div class="stat-value">{{ fmtNumber(stats.total_tokens) }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('stats.totalCost') }}</div>
            <div class="stat-value stat-value--fee">
              <FeeCostCell
                inline
                :credits="stats.total_credits"
                :cost-usd="stats.total_cost_usd"
                :show-cost="showCost"
              />
            </div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('stats.uniqueKeys') }}</div>
            <div class="stat-value">{{ stats.unique_keys }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('stats.uniqueModels') }}</div>
            <div class="stat-value">{{ stats.unique_models }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('stats.uniqueApps') }}</div>
            <div class="stat-value">{{ stats.unique_apps }}</div>
          </div>
        </div>

        <div v-if="stats" class="stats-tables">
          <h3>{{ tt('stats.byModel') }}</h3>
          <table class="table">
            <thead><tr><th>{{ tt('stats.colModel') }}</th><th>{{ tt('stats.colRequests') }}</th><th>{{ tt('stats.colTokens') }}</th><th>{{ tt('stats.colCost') }}</th></tr></thead>
            <tbody>
              <tr v-for="m in stats.by_model" :key="m.model">
                <td><code>{{ m.model }}</code></td>
                <td>{{ fmtNumber(m.requests) }}</td>
                <td>{{ fmtNumber(m.tokens) }}</td>
                <td>
                  <FeeCostCell
                    :credits="m.credits"
                    :cost-usd="m.cost_usd"
                    :show-cost="showCost"
                  />
                </td>
              </tr>
            </tbody>
          </table>

          <h3>{{ tt('stats.byApp') }}</h3>
          <table class="table">
            <thead><tr><th>{{ tt('stats.colApp') }}</th><th>{{ tt('stats.colRequests') }}</th><th>{{ tt('stats.colTokens') }}</th><th>{{ tt('stats.colCost') }}</th></tr></thead>
            <tbody>
              <tr v-for="a in stats.by_application" :key="a.application_code">
                <td><span class="badge badge-blue">{{ a.application_code }}</span></td>
                <td>{{ fmtNumber(a.requests) }}</td>
                <td>{{ fmtNumber(a.tokens) }}</td>
                <td>
                  <FeeCostCell
                    :credits="a.credits"
                    :cost-usd="a.cost_usd"
                    :show-cost="showCost"
                  />
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>

      <!-- Wallet Tab -->
      <div v-if="activeTab === 'wallet'" class="tab-content">
        <div v-if="maasWallet" class="stat-cards">
          <div class="stat-card">
            <div class="stat-label">{{ tt('wallet.quotaRemaining') }}</div>
            <div class="stat-value">{{ fmtNumber(maasWallet.quota_remaining) }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('wallet.grantedBalance') }}</div>
            <div class="stat-value">{{ fmtNumber(maasWallet.granted_balance) }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('wallet.purchasedBalance') }}</div>
            <div class="stat-value">{{ fmtNumber(maasWallet.purchased_balance) }}</div>
          </div>
          <div class="stat-card">
            <div class="stat-label">{{ tt('wallet.totalAvailable') }}</div>
            <div class="stat-value">{{ fmtNumber(maasWallet.total_available) }}</div>
          </div>
        </div>

        <div class="adjust-form">
          <h3>{{ tt('wallet.grantTitle') }}</h3>
          <div class="adjust-row">
            <label>{{ tt('wallet.grantAmountLabel') }}</label>
            <input v-model="grantAmount" type="number" min="1" :placeholder="tt('wallet.grantAmountPlaceholder')" />
          </div>
          <div class="adjust-row">
            <label>{{ tt('wallet.grantNoteLabel') }}</label>
            <input v-model="grantNote" type="text" :placeholder="tt('wallet.grantNotePlaceholder')" />
          </div>
          <button class="btn btn-primary btn-sm" :disabled="grantSaving" @click="submitGrant">
            {{ grantSaving ? tt('wallet.grantSubmitting') : tt('wallet.grantSubmit') }}
          </button>
        </div>

        <div class="adjust-form">
          <h3>{{ tt('wallet.adjustTitle') }}</h3>
          <div class="adjust-row">
            <label>{{ tt('wallet.adjustAmountLabel') }}</label>
            <input v-model="adjustAmount" type="number" :placeholder="tt('wallet.adjustAmountPlaceholder')" />
          </div>
          <div class="adjust-row">
            <label>{{ tt('wallet.adjustNoteLabel') }}</label>
            <input v-model="adjustNote" type="text" :placeholder="tt('wallet.adjustNotePlaceholder')" />
          </div>
          <button class="btn btn-primary btn-sm" :disabled="adjustSaving" @click="submitAdjust">
            {{ adjustSaving ? tt('wallet.adjustSubmitting') : tt('wallet.adjustSubmit') }}
          </button>
        </div>
      </div>

      <!-- Orders Tab -->
      <div v-if="activeTab === 'orders'" class="tab-content">
        <table class="table" style="width:100%">
          <thead>
            <tr>
              <th>{{ tt('orders.colOrderNo') }}</th>
              <th>{{ tt('orders.colType') }}</th>
              <th>{{ tt('orders.colAmount') }}</th>
              <th>{{ tt('orders.colCredits') }}</th>
              <th>{{ tt('orders.colStatus') }}</th>
              <th>{{ tt('orders.colTime') }}</th>
              <th>{{ tt('orders.colActions') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="o in maasOrders" :key="o.id">
              <td class="mono">{{ o.order_no }}</td>
              <td>{{ o.order_type === 'subscribe' ? tt('orders.typeSubscribe') : tt('orders.typeTopup') }}</td>
              <td>¥{{ fmtPrice(o.amount_cents) }}</td>
              <td>{{ fmtNumber(o.credits) }}</td>
              <td>{{ orderStatusLabel(o.status) }}</td>
              <td class="mono">{{ fmtDateTime(o.created_at) }}</td>
              <td>
                <button
                  v-if="o.status === 'pending'"
                  class="btn btn-ghost btn-sm"
                  :disabled="confirmSaving === o.id"
                  @click="confirmOrder(o.id)"
                >
                  {{ confirmSaving === o.id ? tt('orders.confirming') : tt('orders.confirmBtn') }}
                </button>
                <span v-else>—</span>
              </td>
            </tr>
            <tr v-if="maasOrders.length === 0">
              <td colspan="7" style="text-align:center; padding:40px; color: var(--muted)">{{ tt('orders.empty') }}</td>
            </tr>
          </tbody>
        </table>
      </div>

      <!-- Ledger Tab -->
      <div v-if="activeTab === 'ledger'" class="tab-content">
        <table class="table" style="width:100%">
          <thead>
            <tr>
              <th>{{ tt('ledger.colTime') }}</th>
              <th>{{ tt('ledger.colType') }}</th>
              <th>{{ tt('ledger.colPool') }}</th>
              <th class="text-end">{{ tt('ledger.colDelta') }}</th>
              <th class="text-end">{{ tt('ledger.colBalance') }}</th>
              <th>{{ tt('ledger.colRef') }}</th>
              <th>{{ tt('ledger.colNote') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="e in maasLedger" :key="e.id">
              <td class="mono">{{ fmtDateTime(e.created_at) }}</td>
              <td>{{ ledgerTypeLabel(e.entry_type) }}</td>
              <td>{{ poolLabel(e.pool) }}</td>
              <td class="mono text-end">{{ fmtCredits(e.amount) }}</td>
              <td class="mono text-end">{{ fmtNumber(e.balance_after) }}</td>
              <td class="mono">{{ e.ref_type || '—' }} {{ e.ref_id || '' }}</td>
              <td>{{ e.note || '—' }}</td>
            </tr>
            <tr v-if="maasLedger.length === 0">
              <td colspan="7" style="text-align:center; padding:40px; color: var(--muted)">{{ tt('ledger.empty') }}</td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>

    <TenantEditDialog v-if="showEdit && tenant" :tenant="tenant" @close="showEdit = false; loadTenant()" @updated="loadTenant" />
  </div>
</template>

<style scoped>
.tenant-header {
  display: flex;
  align-items: center;
  gap: 16px;
  margin-bottom: 16px;
  padding: 16px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 8px;
}
.text-end { text-align: end; }
.btn-back {
  padding: 6px 12px;
  background: transparent;
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  cursor: pointer;
  font-size: 13px;
}
.btn-back:hover { background: rgba(255,255,255,.05); }
.header-main { flex: 1; }
.header-main h1 {
  font-size: 22px;
  margin: 0 0 8px;
  display: flex;
  align-items: center;
  gap: 12px;
}
.header-meta {
  display: flex;
  gap: 16px;
  font-size: 12px;
  color: var(--muted);
  align-items: center;
}
.code-badge {
  background: var(--bg);
  padding: 2px 8px;
  border-radius: 4px;
  font-family: 'SF Mono', 'Fira Code', monospace;
}
.description {
  font-size: 13px;
  color: var(--text);
  margin: 8px 0 0;
}

.tabs {
  display: flex;
  border-bottom: 1px solid var(--border);
  margin-bottom: 16px;
}
.tabs button {
  padding: 8px 16px;
  background: transparent;
  border: none;
  color: var(--muted);
  cursor: pointer;
  font-size: 13px;
  border-bottom: 2px solid transparent;
}
.tabs button.active {
  color: var(--accent-h);
  border-bottom-color: var(--accent-h);
}

.tab-content {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
}

.stat-cards {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(160px, 1fr));
  gap: 12px;
  margin-bottom: 16px;
}
.stat-card {
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 16px;
  text-align: center;
}
.stat-label { font-size: 12px; color: var(--muted); margin-bottom: 6px; }
.stat-value { font-size: 22px; font-weight: 600; color: var(--text); }
.stat-value--fee :deep(.fee-main) {
  font-size: inherit;
  font-weight: inherit;
}
.stat-value--fee :deep(.fee-cost-sub) {
  font-size: 12px;
  font-weight: 400;
}

.badge-purple { background: rgba(139,92,246,.15); color: #a78bfa; padding: 2px 8px; border-radius: 8px; font-size: 11px; }
.badge-blue { background: rgba(59,130,246,.15); color: #60a5fa; padding: 2px 8px; border-radius: 8px; font-size: 11px; }
.badge-red { background: rgba(239,68,68,.15); color: #f87171; padding: 2px 8px; border-radius: 8px; font-size: 11px; }
.badge-green { background: rgba(34,197,94,.15); color: #4ade80; padding: 2px 8px; border-radius: 8px; font-size: 11px; }
.badge-yellow { background: rgba(234,179,8,.15); color: #fbbf24; padding: 2px 8px; border-radius: 8px; font-size: 11px; }
.badge-gray { background: rgba(156,163,175,.15); color: #9ca3af; padding: 2px 8px; border-radius: 8px; font-size: 11px; }

.mono { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 12px; }

.stats-toolbar {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}
.stats-toolbar select {
  padding: 4px 8px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  font-size: 13px;
}
.stats-tables h3 { font-size: 14px; margin: 16px 0 8px; color: var(--muted); }
.adjust-form {
  margin-top: 20px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
}
.adjust-form h3 { font-size: 14px; margin: 0 0 12px; color: var(--muted); }
.adjust-row {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 10px;
}
.adjust-row label {
  width: 80px;
  font-size: 13px;
  color: var(--muted);
  flex-shrink: 0;
}
.adjust-row input {
  flex: 1;
  padding: 6px 10px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  font-size: 13px;
}
.loading { text-align: center; padding: 40px; color: var(--muted); }
.alert { padding: 8px 12px; border-radius: 4px; font-size: 13px; }
.alert-danger { background: rgba(239,68,68,.1); color: #f87171; border: 1px solid rgba(239,68,68,.3); }

.maas-shortcuts {
  margin-top: 20px;
  padding-top: 16px;
  border-top: 1px solid var(--border);
}
.maas-shortcuts h3 {
  margin: 0 0 6px;
  font-size: 15px;
}
.maas-shortcuts-desc {
  margin: 0 0 12px;
  font-size: 12px;
  color: var(--muted);
}
.maas-shortcut-grid {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(140px, 1fr));
  gap: 10px;
}
.maas-shortcut-card {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 6px;
  padding: 14px 10px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 8px;
  text-decoration: none;
  color: var(--text);
  cursor: pointer;
  font: inherit;
  transition: border-color .15s, background .15s;
}
.maas-shortcut-card:hover {
  border-color: var(--accent-h);
  background: rgba(99,102,241,.06);
}
.maas-shortcut-card--tab {
  background: transparent;
}
.maas-shortcut-icon { font-size: 20px; }
.maas-shortcut-label { font-size: 12px; font-weight: 500; }
</style>
