<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'
import { getUsers, createUser, updateUser, deleteUser, resetUserPassword, getTenantsAdmin } from '../api'
import type { Tenant } from '../api'
import { store, isReadOnlyMode } from '../store'
import { useFormat } from '../i18n/useFormat'

const { t } = useI18n()
const u = (k: string, params?: Record<string, unknown>): string => t(`users.${k}` as never, params as never)
const { fmtDateTime } = useFormat()

const readOnly = computed(() => isReadOnlyMode())

interface User {
  id: number
  tenant_id: string
  username: string
  display_name: string
  email: string
  role: string
  enabled: boolean
  last_login_at: string | null
  created_at: string
}

const users = ref<User[]>([])
const loading = ref(false)
const error = ref('')
const showCreate = ref(false)
const editUser = ref<User | null>(null)
const resetPwdUser = ref<User | null>(null)
const filterTenant = ref<string>('')
const allTenants = ref<Tenant[]>([])
const newPwd = ref('')

// Create form
const form = ref({
  username: '',
  password: '',
  tenant_id: 'default',
  display_name: '',
  email: '',
  role: 'tenant_admin',
})

async function load() {
  loading.value = true
  error.value = ''
  try {
    users.value = await getUsers()
    // Filter by tenant if set
    if (filterTenant.value) {
      users.value = users.value.filter(u => u.tenant_id === filterTenant.value)
    }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : u('error.loadFailed')
  } finally {
    loading.value = false
  }
}

async function handleCreate() {
  if (!form.value.username || !form.value.password) {
    error.value = u('error.usernamePasswordRequired')
    return
  }
  try {
    await createUser(form.value)
    showCreate.value = false
    form.value = { username: '', password: '', tenant_id: 'default', display_name: '', email: '', role: 'tenant_admin' }
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : u('error.createFailed')
  }
}

async function handleToggle(u_: User) {
  try {
    await updateUser(u_.id, { enabled: !u_.enabled })
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : u('error.operationFailed')
  }
}

async function handleDelete(u_: User) {
  if (!confirm(u('confirmDelete', { name: u_.username }))) return
  try {
    await deleteUser(u_.id)
    await load()
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : u('error.deleteFailed')
  }
}

async function handleResetPwd() {
  if (!resetPwdUser.value || newPwd.value.length < 8) {
    error.value = u('error.passwordMinLength')
    return
  }
  try {
    await resetUserPassword(resetPwdUser.value.id, newPwd.value)
    resetPwdUser.value = null
    newPwd.value = ''
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : u('error.resetFailed')
  }
}

function roleLabel(r: string) {
  return r === 'super_admin' ? u('role.super_admin') : u('role.tenant_admin')
}

function fmtDate(s: string | null) {
  if (!s) return '-'
  return fmtDateTime(s)
}

async function loadTenants() {
  try {
    allTenants.value = await getTenantsAdmin()
  } catch { /* ignore */ }
}
onMounted(() => { load(); loadTenants() })
</script>

<template>
  <div class="users-page">
    <div class="page-header">
      <h1>👤 {{ u('title') }}</h1>
      <button v-if="!readOnly" class="btn btn-primary" @click="showCreate = true">+ {{ u('create') }}</button>
    </div>

    <div v-if="readOnly" class="alert alert-info" style="margin-bottom:12px">
      {{ u('readOnlyNotice') }}
    </div>

    <div class="filters">
      <label>{{ u('filter.byTenant') }}</label>
      <select v-model="filterTenant" @change="load">
        <option value="">{{ u('filter.allTenants') }}</option>
        <option v-for="tnt in allTenants" :key="tnt.code" :value="tnt.code">
          {{ tnt.name }} ({{ tnt.code }})
        </option>
      </select>
    </div>

    <div v-if="error" class="alert alert-danger" style="margin-bottom:12px">{{ error }}</div>

    <div v-if="loading" class="loading">{{ u('loadingState') }}</div>

    <table v-else class="table" style="width:100%">
      <thead>
        <tr>
          <th>ID</th>
          <th>{{ u('table.username') }}</th>
          <th>{{ u('table.displayName') }}</th>
          <th>{{ u('table.email') }}</th>
          <th>{{ u('table.tenant') }}</th>
          <th>{{ u('table.role') }}</th>
          <th>{{ u('table.status') }}</th>
          <th>{{ u('table.lastLogin') }}</th>
          <th>{{ u('table.actions') }}</th>
        </tr>
      </thead>
      <tbody>
        <tr v-for="user in users" :key="user.id">
          <td>{{ user.id }}</td>
          <td><strong>{{ user.username }}</strong></td>
          <td>{{ user.display_name || '-' }}</td>
          <td>{{ user.email || '-' }}</td>
          <td><code>{{ user.tenant_id }}</code></td>
          <td><span class="badge" :class="user.role === 'super_admin' ? 'badge-purple' : 'badge-blue'">{{ roleLabel(user.role) }}</span></td>
          <td>
            <span v-if="!readOnly" class="badge" :class="user.enabled ? 'badge-green' : 'badge-red'" style="cursor:pointer" @click="handleToggle(user)">
              {{ user.enabled ? u('status.enabled') : u('status.disabled') }}
            </span>
            <span v-else class="badge" :class="user.enabled ? 'badge-green' : 'badge-red'">
              {{ user.enabled ? u('status.enabled') : u('status.disabled') }}
            </span>
          </td>
          <td>{{ fmtDate(user.last_login_at) }}</td>
          <td>
            <button v-if="!readOnly" class="btn btn-ghost btn-sm" @click="resetPwdUser = user; newPwd = ''">{{ u('action.resetPassword') }}</button>
            <button v-if="!readOnly && user.id !== store.userInfo?.id" class="btn btn-ghost btn-sm" style="color:var(--danger)" @click="handleDelete(user)">{{ u('action.delete') }}</button>
            <span v-else-if="readOnly" class="text-muted" style="font-size:12px;color:var(--muted)">—</span>
          </td>
        </tr>
      </tbody>
    </table>

    <!-- Create Modal -->
    <div v-if="showCreate" class="modal-backdrop" @click.self="showCreate = false">
      <div class="modal-card">
        <h3>{{ u('modal.create.title') }}</h3>
        <div class="form-group">
          <label>{{ u('modal.create.username') }} *</label>
          <input v-model="form.username" placeholder="username" />
        </div>
        <div class="form-group">
          <label>{{ u('modal.create.password') }} *</label>
          <input v-model="form.password" type="password" :placeholder="u('modal.create.passwordPlaceholder')" />
        </div>
        <div class="form-group">
          <label>{{ u('modal.create.displayName') }}</label>
          <input v-model="form.display_name" />
        </div>
        <div class="form-group">
          <label>{{ u('modal.create.email') }}</label>
          <input v-model="form.email" type="email" />
        </div>
        <div class="form-group">
          <label>{{ u('modal.create.tenant') }} *</label>
          <select v-model="form.tenant_id" required>
            <option v-for="tnt in allTenants" :key="tnt.code" :value="tnt.code">
              {{ tnt.name }} ({{ tnt.code }}) - {{ tnt.status }}
            </option>
          </select>
        </div>
        <div class="form-group">
          <label>{{ u('modal.create.role') }}</label>
          <select v-model="form.role">
            <option value="tenant_admin">{{ u('role.tenant_admin') }}</option>
            <option value="super_admin">{{ u('role.super_admin') }}</option>
          </select>
        </div>
        <div class="modal-actions">
          <button class="btn btn-primary" @click="handleCreate">{{ u('modal.create.submit') }}</button>
          <button class="btn btn-ghost" @click="showCreate = false">{{ u('modal.cancel') }}</button>
        </div>
      </div>
    </div>

    <!-- Reset Password Modal -->
    <div v-if="resetPwdUser" class="modal-backdrop" @click.self="resetPwdUser = null">
      <div class="modal-card">
        <h3>{{ u('modal.reset.title', { name: resetPwdUser.username }) }}</h3>
        <div class="form-group">
          <label>{{ u('modal.reset.newPassword') }}</label>
          <input v-model="newPwd" type="password" :placeholder="u('modal.reset.passwordPlaceholder')" />
        </div>
        <div class="modal-actions">
          <button class="btn btn-primary" @click="handleResetPwd">{{ u('modal.reset.submit') }}</button>
          <button class="btn btn-ghost" @click="resetPwdUser = null">{{ u('modal.cancel') }}</button>
        </div>
      </div>
    </div>
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

.badge-purple { background: rgba(139,92,246,.15); color: #a78bfa; }
.badge-blue { background: rgba(59,130,246,.15); color: #60a5fa; }
.badge-green { background: rgba(34,197,94,.15); color: #4ade80; }
.badge-red { background: rgba(239,68,68,.15); color: #f87171; }

.modal-backdrop {
  position: fixed;
  inset: 0;
  background: rgba(0,0,0,.5);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 1000;
}
.modal-card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 24px;
  width: 400px;
  max-height: 90vh;
  overflow-y: auto;
}
.modal-card h3 { margin: 0 0 16px; font-size: 16px; }
.modal-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px; }
</style>
