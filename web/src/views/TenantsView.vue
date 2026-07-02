<script setup lang="ts">
import { ref, onMounted } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { getTenantsAdmin, TENANT_STATUSES, TENANT_STATUS_LABELS, TENANT_STATUS_COLORS } from '../api'
import type { Tenant } from '../api'
import TenantCreateDialog from './TenantCreateDialog.vue'
import FeeCostCell from '../components/FeeCostCell.vue'
import { isPlatformOpsView } from '../store'
import { useFormat } from '../i18n/useFormat'

const router = useRouter()
const { t: td } = useI18n()
const tt = (k: string, params?: Record<string, unknown>): string => td(`tenants.list.${k}` as never, params as never)
const { fmtDateTime, fmtNumber } = useFormat()

const tenants = ref<Tenant[]>([])
const loading = ref(false)
const error = ref('')
const filterStatus = ref<string>('')
const showCreate = ref(false)

async function load() {
  loading.value = true
  error.value = ''
  try {
    tenants.value = await getTenantsAdmin(filterStatus.value || undefined)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('loadFailed')
  } finally {
    loading.value = false
  }
}

function statusColor(s: string) {
  return TENANT_STATUS_COLORS[s] || 'badge-gray'
}

function statusLabel(s: string) {
  return TENANT_STATUS_LABELS[s] || s
}

const showCost = isPlatformOpsView()

function goDetail(t: Tenant) {
  router.push(`/tenants/${t.code}`)
}

onMounted(load)
</script>

<template>
  <div class="tenants-page">
    <div class="page-header">
      <h1>{{ tt('title') }}</h1>
      <button class="btn btn-primary" @click="showCreate = true">{{ tt('createBtn') }}</button>
    </div>

    <div v-if="error" class="alert alert-danger" style="margin-bottom:12px">{{ error }}</div>

    <div class="filters">
      <label>{{ tt('statusLabel') }}:</label>
      <select v-model="filterStatus" @change="load">
        <option value="">{{ tt('allStatuses') }}</option>
        <option v-for="s in TENANT_STATUSES" :key="s" :value="s">{{ statusLabel(s) }}</option>
      </select>
    </div>

    <div v-if="loading" class="loading">{{ tt('loading') }}</div>

    <table v-else class="table tenants-table" style="width:100%">
      <thead>
        <tr>
          <th>{{ tt('colName') }}</th>
          <th>{{ tt('colCode') }}</th>
          <th>{{ tt('colStatus') }}</th>
          <th>{{ tt('colUsers') }}</th>
          <th>{{ tt('colKeys') }}</th>
          <th>{{ tt('colCost7d') }}</th>
          <th>{{ tt('colRequests') }}</th>
          <th>{{ tt('colContact') }}</th>
          <th>{{ tt('colCreated') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr
          v-for="t in tenants"
          :key="t.code"
          class="tenant-row"
          tabindex="0"
          @click="goDetail(t)"
          @keydown.enter="goDetail(t)"
        >
          <td><strong>{{ t.name }}</strong></td>
          <td><code>{{ t.code }}</code></td>
          <td><span class="badge" :class="statusColor(t.status)">{{ statusLabel(t.status) }}</span></td>
          <td>{{ fmtNumber(t.user_count ?? 0) }}</td>
          <td>{{ fmtNumber(t.api_key_count ?? 0) }}</td>
          <td>
            <FeeCostCell
              :credits="t.credits_7d"
              :cost-usd="t.cost_7d_usd"
              :show-cost="showCost"
            />
          </td>
          <td>{{ fmtNumber(t.total_requests ?? 0) }}</td>
          <td>{{ t.contact_email || '-' }}</td>
          <td class="mono">{{ fmtDateTime(t.created_at) }}</td>
        </tr>
        <tr v-if="tenants.length === 0">
          <td colspan="9" style="text-align:center; color: var(--muted); padding: 40px">{{ tt('empty') }}</td>
        </tr>
      </tbody>
    </table>

    <TenantCreateDialog v-if="showCreate" @close="showCreate = false" @created="load" />
  </div>
</template>

<style scoped>
.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
}
.page-header h1 { font-size: 20px; margin: 0; }
.filters {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 12px;
}
.filters label { font-size: 13px; color: var(--muted); }
.filters select {
  padding: 4px 8px;
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  font-size: 13px;
}
.tenants-table .tenant-row {
  cursor: pointer;
}
.tenants-table .tenant-row:hover {
  background: rgba(99, 102, 241, 0.06);
}
.tenants-table .tenant-row:focus-visible {
  outline: 2px solid var(--accent-h);
  outline-offset: -2px;
}
.badge-purple { background: rgba(139,92,246,.15); color: #a78bfa; }
.badge-blue { background: rgba(59,130,246,.15); color: #60a5fa; }
.badge-red { background: rgba(239,68,68,.15); color: #f87171; }
.badge-green { background: rgba(34,197,94,.15); color: #4ade80; }
.badge-yellow { background: rgba(234,179,8,.15); color: #fbbf24; }
.badge-gray { background: rgba(156,163,175,.15); color: #9ca3af; }
.mono { font-family: 'SF Mono', 'Fira Code', monospace; font-size: 12px; }
.loading {
  text-align: center;
  padding: 40px;
  color: var(--muted);
}
</style>
