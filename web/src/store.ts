import { reactive } from 'vue'

const KEY = 'llmgw_api_key'

export const store = reactive({
  apiKey: localStorage.getItem(KEY) ?? '',
})

export function setApiKey(k: string) {
  store.apiKey = k
  localStorage.setItem(KEY, k)
}

export function clearApiKey() {
  store.apiKey = ''
  localStorage.removeItem(KEY)
}
