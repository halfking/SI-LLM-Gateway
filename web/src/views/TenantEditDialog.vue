<script setup lang="ts">
import { ref, watch } from 'vue'
import { useI18n } from 'vue-i18n'
import { updateTenant, TENANT_STATUSES, TENANT_STATUS_LABELS } from '../api'
import type { Tenant } from '../api'

const props = defineProps<{ tenant: Tenant }>()
const emit = defineEmits<{
  (e: 'close'): void
  (e: 'updated'): void
}>()

const { t: td } = useI18n()
const tt = (k: string, params?: Record<string, unknown>): string => td(`tenants.${k}` as never, params as never)

const form = ref({
  name: props.tenant.name,
  status: props.tenant.status,
  description: props.tenant.description,
  contact_email: props.tenant.contact_email,
})
const submitting = ref(false)
const error = ref('')

watch(() => props.tenant, (t) => {
  form.value = {
    name: t.name,
    status: t.status,
    description: t.description,
    contact_email: t.contact_email,
  }
})

async function handleSubmit() {
  if (!form.value.name) {
    error.value = tt('edit.nameRequired')
    return
  }
  submitting.value = true
  error.value = ''
  try {
    await updateTenant(props.tenant.code, {
      name: form.value.name,
      status: form.value.status,
      description: form.value.description,
      contact_email: form.value.contact_email,
    })
    emit('updated')
    emit('close')
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : tt('edit.updateFailed')
  } finally {
    submitting.value = false
  }
}
</script>

<template>
  <div class="modal-backdrop" @click.self="emit('close')">
    <div class="modal-card">
      <h3>{{ tt('edit.title', { code: tenant.code }) }}</h3>
      <div v-if="error" class="alert alert-danger">{{ error }}</div>
      <form @submit.prevent="handleSubmit">
        <div class="form-group">
          <label>{{ tt('edit.nameLabel') }}</label>
          <input v-model="form.name" required />
        </div>
        <div class="form-group">
          <label>{{ tt('edit.statusLabel') }}</label>
          <select v-model="form.status">
            <option v-for="s in TENANT_STATUSES" :key="s" :value="s">{{ TENANT_STATUS_LABELS[s] }}</option>
          </select>
        </div>
        <div class="form-group">
          <label>{{ tt('edit.contactLabel') }}</label>
          <input v-model="form.contact_email" type="email" />
        </div>
        <div class="form-group">
          <label>{{ tt('edit.descLabel') }}</label>
          <textarea v-model="form.description" rows="3" />
        </div>
        <div class="modal-actions">
          <button type="submit" class="btn btn-primary" :disabled="submitting">
            {{ submitting ? tt('edit.saving') : tt('edit.save') }}
          </button>
          <button type="button" class="btn btn-ghost" @click="emit('close')">{{ tt('edit.cancel') }}</button>
        </div>
      </form>
    </div>
  </div>
</template>

<style scoped>
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
  width: 480px;
  max-height: 90vh;
  overflow-y: auto;
}
.modal-card h3 { margin: 0 0 16px; }
.form-group { margin-bottom: 12px; }
.form-group label { display: block; font-size: 13px; margin-bottom: 4px; }
.form-group input, .form-group select, .form-group textarea {
  width: 100%;
  padding: 6px 10px;
  background: var(--bg);
  border: 1px solid var(--border);
  border-radius: 4px;
  color: var(--text);
  font-size: 13px;
  font-family: inherit;
}
.modal-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px; }
.alert { padding: 8px 12px; border-radius: 4px; font-size: 13px; margin-bottom: 12px; }
.alert-danger { background: rgba(239,68,68,.1); color: #f87171; border: 1px solid rgba(239,68,68,.3); }
</style>
