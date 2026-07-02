<script setup lang="ts">
import { useRouter } from 'vue-router'
import { useI18n } from 'vue-i18n'
import { clearAll } from '../store'

const router = useRouter()
const { t: td } = useI18n()
const fb = (k: string): string => td(`forbidden.${k}` as never)

function goHome() {
  router.push('/')
}

function logout() {
  clearAll()
  router.push('/login')
}
</script>

<template>
  <div class="forbidden-page">
    <div class="forbidden-card">
      <div class="forbidden-icon">🔒</div>
      <h1>{{ fb('title') }}</h1>
      <p class="subtitle">{{ fb('subtitle') }}</p>
      <div class="actions">
        <button class="btn btn-primary" @click="goHome">{{ fb('backToDashboard') }}</button>
        <button class="btn btn-ghost" @click="logout">{{ fb('switchAccount') }}</button>
      </div>
    </div>
  </div>
</template>

<style scoped>
.forbidden-page {
  min-height: 100vh;
  display: flex;
  align-items: center;
  justify-content: center;
  background: var(--bg);
}
.forbidden-card {
  background: var(--card);
  border: 1px solid var(--border);
  border-radius: 12px;
  padding: 48px 40px;
  text-align: center;
  max-width: 480px;
}
.forbidden-icon {
  font-size: 64px;
  margin-bottom: 16px;
}
h1 {
  font-size: 24px;
  margin: 0 0 12px;
  color: var(--text);
}
.subtitle {
  color: var(--muted);
  font-size: 14px;
  line-height: 1.6;
  margin-bottom: 28px;
}
.actions {
  display: flex;
  gap: 12px;
  justify-content: center;
}
</style>
