<script setup lang="ts">
import { ref, computed, onMounted } from 'vue'
import { getProviders, type Provider } from '../api'
import { store } from '../store'
import ModelPicker from '../components/ModelPicker.vue'

const providers = ref<Provider[]>([])
const selectedModel = ref('gpt-4o-mini')
const apiKey = computed(() => store.apiKey || '<YOUR_API_KEY>')

const baseUrl = computed(() => {
  return window.location.origin + '/v1'
})

const curlExample = computed(() => `curl ${baseUrl.value}/chat/completions \\
  -H "Content-Type: application/json" \\
  -H "Authorization: Bearer ${apiKey.value}" \\
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
    api_key="${apiKey.value}",
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
    api_key="${apiKey.value}",
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
  apiKey: "${apiKey.value}",
  baseURL: "${baseUrl.value}",
  dangerouslyAllowBrowser: true,  // only for demo
});

const response = await client.chat.completions.create({
  model: "${selectedModel.value}",
  messages: [{ role: "user", content: "Hello!" }],
  max_tokens: 256,
});

console.log(response.choices[0].message.content);`)

const listModelsExample = computed(() => `curl ${baseUrl.value}/models \\
  -H "Authorization: Bearer ${apiKey.value}"`)

const copied = ref<string | null>(null)
function copyCode(key: string, text: string) {
  navigator.clipboard.writeText(text)
  copied.value = key
  setTimeout(() => { copied.value = null }, 2000)
}

onMounted(async () => {
  try {
    providers.value = await getProviders()
  } catch { /* ignore */ }
})
</script>

<template>
  <div>
    <div class="page-header">
      <h2>请求示例</h2>
    </div>

    <p style="color:var(--muted);margin-bottom:20px">
      网关兼容 OpenAI API 协议。将 <code>base_url</code> 指向此网关即可使用任意支持的模型。
    </p>

    <!-- Model selector -->
    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;align-items:center;gap:16px;flex-wrap:wrap">
        <div style="font-weight:500;white-space:nowrap">选择示例模型：</div>
        <div style="max-width:320px;flex:1;min-width:240px">
          <ModelPicker
            v-model="selectedModel"
            :allow-free-text="true"
            placeholder="选择或输入模型名"
          />
        </div>
        <div style="font-size:12px;color:var(--muted)">
          Base URL: <code>{{ baseUrl }}</code>
        </div>
      </div>
    </div>

    <!-- cURL -->
    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">cURL — Chat Completions</h4>
        <button class="btn btn-ghost btn-sm" @click="copyCode('curl', curlExample)">
          {{ copied === 'curl' ? '已复制!' : '复制' }}
        </button>
      </div>
      <pre class="code-block">{{ curlExample }}</pre>
    </div>

    <!-- Python -->
    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">Python (openai SDK)</h4>
        <button class="btn btn-ghost btn-sm" @click="copyCode('python', pythonExample)">
          {{ copied === 'python' ? '已复制!' : '复制' }}
        </button>
      </div>
      <pre class="code-block">{{ pythonExample }}</pre>
    </div>

    <!-- Python streaming -->
    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">Python — 流式输出 (Streaming)</h4>
        <button class="btn btn-ghost btn-sm" @click="copyCode('stream', streamExample)">
          {{ copied === 'stream' ? '已复制!' : '复制' }}
        </button>
      </div>
      <pre class="code-block">{{ streamExample }}</pre>
    </div>

    <!-- JavaScript -->
    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">JavaScript / TypeScript (openai SDK)</h4>
        <button class="btn btn-ghost btn-sm" @click="copyCode('js', jsExample)">
          {{ copied === 'js' ? '已复制!' : '复制' }}
        </button>
      </div>
      <pre class="code-block">{{ jsExample }}</pre>
    </div>

    <!-- List models -->
    <div class="card" style="margin-bottom:20px">
      <div style="display:flex;justify-content:space-between;align-items:center;margin-bottom:12px">
        <h4 style="margin:0">cURL — 列出可用模型</h4>
        <button class="btn btn-ghost btn-sm" @click="copyCode('models', listModelsExample)">
          {{ copied === 'models' ? '已复制!' : '复制' }}
        </button>
      </div>
      <pre class="code-block">{{ listModelsExample }}</pre>
    </div>
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
</style>
