<script setup lang="ts">
import { ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { login, getAuthMe } from '../api'
import { setApiKey, setJwtToken, setUserInfo } from '../store'
import { useLoginModal } from '../composables/useLoginModal'

const props = defineProps<{
  modelValue: boolean
}>()

const emit = defineEmits<{
  'update:modelValue': [value: boolean]
}>()

const router = useRouter()
const { closeLogin } = useLoginModal()
const { t } = useI18n()

const username = ref('admin')
const password = ref('')
const loading = ref(false)
const error = ref('')

watch(
  () => props.modelValue,
  (open) => {
    if (open) {
      error.value = ''
      password.value = ''
    }
  },
)

function close() {
  emit('update:modelValue', false)
  closeLogin()
}

async function handleLogin() {
  error.value = ''
  if (!username.value || !password.value) {
    error.value = t('login.error.required')
    return
  }
  loading.value = true
  try {
    const resp = await login(username.value, password.value)
    if (resp.access_token) {
      setJwtToken(resp.access_token)
      if (resp.user) {
        setUserInfo(resp.user)
      } else {
        try {
          const me = await getAuthMe()
          setUserInfo(me)
        } catch { /* ignore */ }
      }
    } else if (resp.api_key) {
      setApiKey(resp.api_key)
    }
    close()
    const redirect = typeof router.currentRoute.value.query.redirect === 'string'
      ? router.currentRoute.value.query.redirect
      : '/'
    const target = redirect.startsWith('/') ? redirect : '/'
    if (router.currentRoute.value.path === '/login' || router.currentRoute.value.query.login) {
      await router.replace(target)
    }
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : t('login.error.failed')
  } finally {
    loading.value = false
  }
}
</script>

<template>
  <Teleport to="body">
    <div
      v-if="modelValue"
      class="modal-overlay"
      role="presentation"
      @click.self="close"
    >
      <div
        class="login-modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="login-modal-title"
        @click.stop
      >
        <div class="login-modal__header">
          <div class="login-modal__brand">
            <svg width="32" height="32" viewBox="0 0 32 32" aria-hidden="true">
              <circle cx="16" cy="16" r="14" fill="#6366f1" />
              <text
                x="16"
                y="21"
                text-anchor="middle"
                font-size="16"
                fill="white"
                font-family="Arial,sans-serif"
                font-weight="bold"
              >G</text>
            </svg>
            <div>
              <h2 id="login-modal-title">{{ t('login.title') }}</h2>
              <p class="login-modal__subtitle">{{ t('login.subtitle') }}</p>
            </div>
          </div>
          <button type="button" class="btn btn-ghost btn-sm login-modal__close" :aria-label="t('login.close')" @click="close">
            ✕
          </button>
        </div>

        <div v-if="error" class="alert alert-danger">{{ error }}</div>

        <form @submit.prevent="handleLogin">
          <div class="form-group">
            <label for="login-username">{{ t('login.username') }}</label>
            <input
              id="login-username"
              v-model="username"
              type="text"
              :placeholder="t('login.usernamePlaceholder')"
              autocomplete="username"
            />
          </div>
          <div class="form-group">
            <label for="login-password">{{ t('login.password') }}</label>
            <input
              id="login-password"
              v-model="password"
              type="password"
              :placeholder="t('login.passwordPlaceholder')"
              autocomplete="current-password"
            />
          </div>
          <div class="login-modal__actions">
            <button type="button" class="btn btn-ghost" @click="close">{{ t('login.cancel') }}</button>
            <button class="btn btn-primary" type="submit" :disabled="loading">
              {{ loading ? t('login.submitting') : t('login.submit') }}
            </button>
          </div>
        </form>
      </div>
    </div>
  </Teleport>
</template>

<style scoped>
.login-modal {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 24px;
  width: min(400px, calc(100vw - 32px));
  box-shadow: 0 16px 48px rgba(0, 0, 0, 0.45);
}

.login-modal__header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
  margin-bottom: 20px;
}

.login-modal__brand {
  display: flex;
  align-items: center;
  gap: 12px;
}

.login-modal__brand h2 {
  margin: 0;
  font-size: 17px;
  font-weight: 600;
}

.login-modal__subtitle {
  margin: 2px 0 0;
  font-size: 12px;
  color: var(--muted);
}

.login-modal__close {
  flex-shrink: 0;
  min-width: 32px;
  padding: 4px 8px;
}

.login-modal__actions {
  display: flex;
  justify-content: flex-end;
  gap: 8px;
  margin-top: 8px;
}
</style>
