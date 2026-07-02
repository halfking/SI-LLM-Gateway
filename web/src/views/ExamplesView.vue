<script setup lang="ts">
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { resolveRouting } from '../api'
import ModelPicker from '../components/ModelPicker.vue'
import ClientConfigGenerator from '../components/ClientConfigGenerator.vue'
import { useGatewayApiKey } from '../composables/useGatewayApiKey'

const { t } = useI18n()
const tx = (k: string, params?: Record<string, unknown>): string =>
  t(`examples.${k}` as never, params as never)

const { apiKey: gatewayApiKey } = useGatewayApiKey()

const selectedModel = ref('glm-4-flash')
const realApiKey = computed(() => gatewayApiKey.value || '')
const maskedApiKey = computed(() => {
  const k = realApiKey.value
  if (!k) return tx('placeholder')
  if (k.length <= 16) return `${k.slice(0, 4)}****`
  return `${k.slice(0, 12)}****${k.slice(-4)}`
})
const baseUrl = computed(() => window.location.origin + '/v1')

const curlExample = computed(() => `curl ${baseUrl.value}/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer ${maskedApiKey.value}" \\
  -d '{
    "model": "${selectedModel.value}",
    "messages": [
      {"role": "system", "content": "You are a helpful assistant."},
      {"role": "user", "content": "Hello!"}
    ],
    "max_tokens": 256
  }'`)

const pythonExample = computed(() => `from openai import OpenAI

client = OpenAI(
    api_key="${maskedApiKey.value}",
    base_url="${baseUrl.value}",
)

response = client.chat.completions.create(
    model="${selectedModel.value}",
    messages=[
        {"role": "system", "content": "You are a helpful assistant."},
        {"role": "user", "content": "Hello!"},
    ],
    max_tokens=256,
)

print(response.choices[0].message.content)`)

const streamExample = computed(() => `from openai import OpenAI

client = OpenAI(
    api_key="${maskedApiKey.value}",
    base_url="${baseUrl.value}",
)

with client.chat.completions.stream(
    model="${selectedModel.value}",
    messages=[{"role": "user", "content": "Count to 5."}],
    max_tokens=64,
) as stream:
    for chunk in stream:
        delta = chunk.choices[0].delta.content or ""
        print(delta, end="", flush=True)`)

const jsExample = computed(() => `import OpenAI from "openai";

const client = new OpenAI({
  apiKey: "${maskedApiKey.value}",
  baseURL: "${baseUrl.value}",
  dangerouslyAllowBrowser: true,
});

const response = await client.chat.completions.create({
  model: "${selectedModel.value}",
  messages: [{ role: "user", content: "Hello!" }],
  max_tokens: 256,
});

console.log(response.choices[0].message.content);`)

const listModelsExample = computed(() => `curl ${baseUrl.value}/models \\
  -H "Authorization: Bearer ${maskedApiKey.value}"`)

const copied = ref<string | null>(null)
function copyCode(key: string, text: string) {
  navigator.clipboard.writeText(text)
  copied.value = key
  setTimeout(() => { copied.value = null }, 2000)
}

type ExampleId = 'curl' | 'python' | 'stream' | 'js' | 'models'
type TestKind = 'chat' | 'stream' | 'models'

interface DrawerState {
  open: boolean
  exampleId: ExampleId
  testKind: TestKind
  loading: boolean
  status: number
  latency: number
  error: string
  requestBody: string
  responseBody: string
  routing: string
}

const emptyDrawer = (exampleId: ExampleId, testKind: TestKind): DrawerState => ({
  open: false,
  exampleId,
  testKind,
  loading: false,
  status: 0,
  latency: 0,
  error: '',
  requestBody: '',
  responseBody: '',
  routing: '',
})

const drawers = ref<Record<ExampleId, DrawerState>>({
  curl: emptyDrawer('curl', 'chat'),
  python: emptyDrawer('python', 'chat'),
  stream: emptyDrawer('stream', 'stream'),
  js: emptyDrawer('js', 'chat'),
  models: emptyDrawer('models', 'models'),
})

async function runTest(exampleId: ExampleId) {
  const d = drawers.value[exampleId]
  d.open = true
  d.loading = true
  d.status = 0
  d.latency = 0
  d.error = ''
  d.responseBody = ''
  d.routing = ''
  d.requestBody = ''

  let reqBody: Record<string, unknown> | null = null
  let url = `${baseUrl.value}/chat/completions`
  let method = 'POST'
  let headers: Record<string, string> = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${realApiKey.value}`,
  }

  if (d.testKind === 'models') {
    url = `${baseUrl.value}/models`
    method = 'GET'
    headers = { 'Authorization': `Bearer ${realApiKey.value}` }
    d.requestBody = `GET ${url}`
  } else {
    const isStream = d.testKind === 'stream'
    const msgs = isStream
      ? [{ role: 'user', content: 'Count to 5.' }]
      : [
          { role: 'system', content: 'You are a helpful assistant.' },
          { role: 'user', content: 'Hello!' },
        ]
    reqBody = {
      model: selectedModel.value,
      messages: msgs,
      max_tokens: isStream ? 64 : 256,
      ...(isStream ? { stream: true } : {}),
    }
    d.requestBody = JSON.stringify(reqBody, null, 2)
  }

  const start = performance.now()
  try {
    const resp = await fetch(url, {
      method,
      headers,
      body: reqBody ? JSON.stringify(reqBody) : undefined,
    })
    d.latency = Math.round(performance.now() - start)
    d.status = resp.status
    const text = await resp.text()

    if (d.testKind === 'stream') {
      const lines = text.split('\n').filter(l => l.startsWith('data: '))
      let full = ''
      for (const line of lines) {
        const json = line.slice(6).trim()
        if (json === '[DONE]') break
        try {
          const obj = JSON.parse(json)
          const delta = obj?.choices?.[0]?.delta?.content
          if (delta) full += delta
        } catch { /* skip */ }
      }
      d.responseBody = full || text.slice(0, 2000)
    } else {
      try {
        const parsed = JSON.parse(text)
        d.responseBody = JSON.stringify(parsed, null, 2).slice(0, 4000)
      } catch {
        d.responseBody = text.slice(0, 4000)
      }
    }

    if (realApiKey.value) {
      try {
        const route = await resolveRouting(selectedModel.value)
        d.routing =
          `${tx('routing.rawModel', { client_model: route.client_model })}\n` +
          `${route.canonical_name ? tx('routing.canonical', { canonical: route.canonical_name }) : tx('routing.fallbackCanonical')}\n` +
          `${tx('routing.path', { path: route.resolution_path })}\n` +
          `${tx('routing.candidates', { n: route.candidates?.length || 0 })}\n` +
          `${route.raw_models?.length ? tx('routing.rawList', { list: route.raw_models.join(', ') }) : tx('routing.fallbackModel')}`
      } catch {
        d.routing = tx('routing.failed')
      }
    }
  } catch (err: any) {
    d.latency = Math.round(performance.now() - start)
    d.error = err.message || String(err)
  } finally {
    d.loading = false
  }
}

function closeDrawer(exampleId: ExampleId) {
  drawers.value[exampleId].open = false
}

const exampleTitle = computed<Record<ExampleId, string>>(() => ({
  curl: tx('drawer.titleCurl'),
  python: tx('drawer.titlePython'),
  stream: tx('drawer.titleStream'),
  js: tx('drawer.titleJs'),
  models: tx('drawer.titleModels'),
}))

type ClientGuideId = 'cherry' | 'cursor' | 'claude' | 'roocode'
const openGuide = ref<ClientGuideId | null>('cherry')

interface ClientGuide {
  id: ClientGuideId
  name: string
  icon: string
  steps: string[]
  mcpNote?: string
}

const clientGuides = computed((): ClientGuide[] => [
  {
    id: 'cherry',
    name: tx('guides.cherry.name'),
    icon: '🍒',
    steps: [
      tx('guides.cherry.steps[0]'),
      tx('guides.cherry.steps[1]', { url: baseUrl.value }),
      tx('guides.cherry.steps[2]'),
      tx('guides.cherry.steps[3]'),
      tx('guides.cherry.steps[4]'),
    ],
    mcpNote: tx('guides.cherry.mcp'),
  },
  {
    id: 'cursor',
    name: tx('guides.cursor.name'),
    icon: '⌨️',
    steps: [
      tx('guides.cursor.steps[0]'),
      tx('guides.cursor.steps[1]'),
      tx('guides.cursor.steps[2]', { url: baseUrl.value }),
      tx('guides.cursor.steps[3]'),
      tx('guides.cursor.steps[4]'),
      tx('guides.cursor.steps[5]'),
    ],
    mcpNote: tx('guides.cursor.mcp'),
  },
  {
    id: 'claude',
    name: tx('guides.claude.name'),
    icon: '🤖',
    steps: [
      tx('guides.claude.steps[0]'),
      tx('guides.claude.steps[1]'),
      tx('guides.claude.steps[2]'),
      tx('guides.claude.steps[3]'),
      tx('guides.claude.steps[4]', { url: baseUrl.value }),
    ],
  },
  {
    id: 'roocode',
    name: tx('guides.roocode.name'),
    icon: '🧩',
    steps: [
      tx('guides.roocode.steps[0]'),
      tx('guides.roocode.steps[1]', { url: baseUrl.value }),
      tx('guides.roocode.steps[2]'),
      tx('guides.roocode.steps[3]'),
      tx('guides.roocode.steps[4]'),
    ],
    mcpNote: tx('guides.roocode.mcp'),
  },
])

function toggleGuide(id: ClientGuideId) {
  openGuide.value = openGuide.value === id ? null : id
}
</script>

<template>
  <div>
    <div class="page-header">
      <h2>{{ tx('title') }}</h2>
    </div>

    <p style="color:var(--muted);margin-bottom:12px" v-html="tx('intro')">
    </p>

    <h3 class="section-heading">{{ tx('sectionClientConfig') }}</h3>
    <ClientConfigGenerator />

    <div class="guide-list">
      <div v-for="g in clientGuides" :key="g.id" class="card guide-card">
        <button type="button" class="guide-header" @click="toggleGuide(g.id)">
          <span class="guide-title"><span class="guide-icon">{{ g.icon }}</span> {{ g.name }}</span>
          <span class="guide-chevron">{{ openGuide === g.id ? '▼' : '▶' }}</span>
        </button>
        <div v-show="openGuide === g.id" class="guide-body">
          <ol class="guide-steps">
            <li v-for="(step, i) in g.steps" :key="i">{{ step }}</li>
          </ol>
          <p v-if="g.mcpNote" class="guide-mcp">{{ g.mcpNote }}</p>
        </div>
      </div>
    </div>

    <h3 class="section-heading" style="margin-top:28px">{{ tx('sectionApiExamples') }}</h3>
    <p v-if="realApiKey" class="key-hint">
      {{ tx('keyHint') }}
      <button type="button" class="btn btn-ghost btn-sm" @click="copyCode('realkey', realApiKey)">
        {{ copied === 'realkey' ? tx('copied') : tx('copyKey') }}
      </button>
    </p>

    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;align-items:center;gap:16px;flex-wrap:wrap">
        <div style="font-weight:500;white-space:nowrap">{{ tx('selectModel') }}</div>
        <div style="max-width:360px;flex:1;min-width:240px">
          <ModelPicker
            v-model="selectedModel"
            :placeholder="tx('modelPickerPlaceholder')"
            :title="tx('modelPickerTitle')"
          />
        </div>
        <div style="font-size:12px;color:var(--muted)">
          {{ tx('currentModel') }} <code style="color:var(--accent)">{{ selectedModel }}</code>
        </div>
        <div style="font-size:12px;color:var(--muted)">
          {{ tx('baseUrlLabel') }} <code>{{ baseUrl }}</code>
        </div>
      </div>
    </div>

    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">{{ tx('example.curl') }}</h4>
        <div style="display:flex;gap:8px">
          <button class="btn btn-ghost btn-sm" @click="copyCode('curl', curlExample)">
            {{ copied === 'curl' ? tx('copied') : tx('button.copy') }}
          </button>
          <button class="btn btn-primary btn-sm" @click="runTest('curl')" :disabled="drawers.curl.loading">
            {{ drawers.curl.loading ? tx('button.testing') : tx('button.test') }}
          </button>
        </div>
      </div>
      <pre class="code-block">{{ curlExample }}</pre>
    </div>

    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">{{ tx('example.python') }}</h4>
        <div style="display:flex;gap:8px">
          <button class="btn btn-ghost btn-sm" @click="copyCode('python', pythonExample)">
            {{ copied === 'python' ? tx('copied') : tx('button.copy') }}
          </button>
          <button class="btn btn-primary btn-sm" @click="runTest('python')" :disabled="drawers.python.loading">
            {{ drawers.python.loading ? tx('button.testing') : tx('button.test') }}
          </button>
        </div>
      </div>
      <pre class="code-block">{{ pythonExample }}</pre>
    </div>

    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">{{ tx('example.stream') }}</h4>
        <div style="display:flex;gap:8px">
          <button class="btn btn-ghost btn-sm" @click="copyCode('stream', streamExample)">
            {{ copied === 'stream' ? tx('copied') : tx('button.copy') }}
          </button>
          <button class="btn btn-primary btn-sm" @click="runTest('stream')" :disabled="drawers.stream.loading">
            {{ drawers.stream.loading ? tx('button.testing') : tx('button.test') }}
          </button>
        </div>
      </div>
      <pre class="code-block">{{ streamExample }}</pre>
    </div>

    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">{{ tx('example.js') }}</h4>
        <div style="display:flex;gap:8px">
          <button class="btn btn-ghost btn-sm" @click="copyCode('js', jsExample)">
            {{ copied === 'js' ? tx('copied') : tx('button.copy') }}
          </button>
          <button class="btn btn-primary btn-sm" @click="runTest('js')" :disabled="drawers.js.loading">
            {{ drawers.js.loading ? tx('button.testing') : tx('button.test') }}
          </button>
        </div>
      </div>
      <pre class="code-block">{{ jsExample }}</pre>
    </div>

    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">{{ tx('example.models') }}</h4>
        <div style="display:flex;gap:8px">
          <button class="btn btn-ghost btn-sm" @click="copyCode('models', listModelsExample)">
            {{ copied === 'models' ? tx('copied') : tx('button.copy') }}
          </button>
          <button class="btn btn-primary btn-sm" @click="runTest('models')" :disabled="drawers.models.loading">
            {{ drawers.models.loading ? tx('button.testing') : tx('button.test') }}
          </button>
        </div>
      </div>
      <pre class="code-block">{{ listModelsExample }}</pre>
    </div>

    <template v-for="eid in (['curl','python','stream','js','models'] as ExampleId[])" :key="eid">
      <div v-if="drawers[eid].open" class="drawer-backdrop" @click="closeDrawer(eid)">
        <div class="drawer-panel card" @click.stop>
          <div class="drawer-header">
            <h4 style="margin:0">{{ exampleTitle[eid] }}</h4>
            <div style="display:flex;align-items:center;gap:12px">
              <span style="font-size:13px;color:var(--muted)">{{ tx('drawer.model', { model: selectedModel }) }}</span>
              <button class="btn btn-ghost btn-sm" @click="closeDrawer(eid)">{{ tx('button.close') }}</button>
            </div>
          </div>

          <div v-if="drawers[eid].loading" class="drawer-loading">
            <div class="spinner"></div>
            <span>{{ tx('drawer.requesting') }}</span>
          </div>

          <template v-else>
            <div class="drawer-meta">
              <div class="meta-item">
                <span class="meta-label">{{ tx('drawer.status') }}</span>
                <span :class="drawers[eid].status >= 200 && drawers[eid].status < 300 ? 'badge badge-green' : 'badge badge-red'">{{ drawers[eid].status || '—' }}</span>
              </div>
              <div class="meta-item">
                <span class="meta-label">{{ tx('drawer.latency') }}</span>
                <span>{{ drawers[eid].latency }}ms</span>
              </div>
              <div class="meta-item">
                <span class="meta-label">{{ tx('drawer.type') }}</span>
                <code>{{ drawers[eid].testKind }}</code>
              </div>
            </div>

            <div v-if="drawers[eid].error" class="alert alert-danger" style="margin:0 0 12px">
              {{ drawers[eid].error }}
            </div>

            <div v-if="drawers[eid].requestBody" class="drawer-section">
              <div class="section-title">{{ tx('drawer.requestBody') }}</div>
              <pre class="code-block compact">{{ drawers[eid].requestBody }}</pre>
            </div>

            <div v-if="drawers[eid].responseBody" class="drawer-section">
              <div class="section-title">{{ tx('drawer.responseBody') }}</div>
              <pre class="code-block compact">{{ drawers[eid].responseBody }}</pre>
            </div>

            <div v-if="drawers[eid].routing" class="drawer-section">
              <div class="section-title">{{ tx('drawer.routing') }}</div>
              <pre class="code-block compact">{{ drawers[eid].routing }}</pre>
            </div>
          </template>
        </div>
      </div>
    </template>
  </div>
</template>

<style scoped>
.code-block {
  background: #1a1d23;
  color: #e2e8f0;
  border-radius: 8px;
  padding: 16px;
  overflow-x: auto;
  font-size: 13px;
  line-height: 1.6;
  white-space: pre;
  margin: 0;
}
.code-block.compact {
  padding: 12px;
  font-size: 12px;
  max-height: 240px;
  overflow: auto;
}

.drawer-loading {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 12px;
  padding: 40px 0;
  color: var(--muted);
}

.spinner {
  width: 20px;
  height: 20px;
  border: 2px solid var(--border);
  border-top-color: var(--accent);
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
}

@keyframes spin {
  to { transform: rotate(360deg); }
}

.drawer-meta {
  display: flex;
  gap: 20px;
  margin-bottom: 16px;
  font-size: 13px;
  flex-wrap: wrap;
}

.meta-item {
  display: flex;
  align-items: center;
  gap: 6px;
}

.meta-label {
  color: var(--muted);
}

.key-hint {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  font-size: 12px;
  color: var(--muted);
  margin-bottom: 16px;
}

.section-heading {
  font-size: 15px;
  font-weight: 600;
  margin: 0 0 12px;
}

.guide-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
  margin-bottom: 8px;
}

.guide-card {
  padding: 0;
  overflow: hidden;
}

.guide-header {
  width: 100%;
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 14px 16px;
  background: none;
  border: none;
  color: var(--text);
  font-size: 14px;
  font-weight: 500;
  cursor: pointer;
  text-align: left;
}

.guide-header:hover {
  background: rgba(255, 255, 255, 0.03);
}

.guide-title {
  display: flex;
  align-items: center;
  gap: 8px;
}

.guide-icon {
  font-size: 18px;
}

.guide-chevron {
  color: var(--muted);
  font-size: 12px;
}

.guide-body {
  padding: 0 16px 16px;
  border-top: 1px solid var(--border);
}

.guide-steps {
  margin: 12px 0 0;
  padding-left: 20px;
  font-size: 13px;
  line-height: 1.7;
  color: var(--text);
}

.guide-mcp {
  margin: 12px 0 0;
  padding: 10px 12px;
  font-size: 12px;
  line-height: 1.6;
  color: var(--muted);
  background: rgba(99, 102, 241, 0.08);
  border-radius: 6px;
}
</style>
