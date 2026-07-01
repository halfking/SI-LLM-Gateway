import { createApp, nextTick } from 'vue'
import App from './App.vue'
import { router } from './router'
import { enableAuthRedirect } from './api/_core'
import { i18n } from './i18n'
import './style.css'

const app = createApp(App)
// vue-i18n must be installed before any component calls useI18n(); App.vue
// and the per-view components use t() in <script setup>, so missing this
// `app.use(i18n)` causes useI18n() to throw "NOT_INSTALLED" → SyntaxError →
// blank page (root cause of the 2026-07-02 llm.kxpms.cn white screen).
app.use(router)
app.use(i18n)
app.mount('#app')

// Re-enable the api/_core 401 → /login redirect AFTER the very first
// paint has settled. The redirect is suppressed during the initial
// mount window so that a stale token does not produce a one-frame
// flash of the protected page followed by an immediate jump to /login
// (reported as "页面闪了一下就消失了", 2026-06-26).
// Two animation frames give the layout a chance to commit before any
// background fetch failure can yank the user away.
requestAnimationFrame(() => {
  requestAnimationFrame(() => {
    nextTick(() => {
      enableAuthRedirect()
    })
  })
})
