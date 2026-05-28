<script setup lang="ts">
import { ref, onMounted, onUnmounted } from 'vue'
import { getDecisions, type RoutingDecision } from '../api'
import ModelPicker from '../components/ModelPicker.vue'

const rows = ref<RoutingDecision[]>([])
const loading = ref(false)
const error = ref<string | null>(null)
const sinceMinutes = ref(30)
const filterModel = ref('')
const filterSuccess = ref<'' | 'true' | 'false'>('')
const limit = ref(50)

let timer: ReturnType<typeof setInterval> | null = null

async function load() {
  loading.value = true
  error.value = null
  try {
    const params: Record<string, unknown> = {
      since_minutes: sinceMinutes.value,
      limit: limit.value,
    }
    if (filterModel.value.trim()) params.model = filterModel.value.trim()
    if (filterSuccess.value !== '') params.success = filterSuccess.value === 'true'
    rows.value = await getDecisions(params)
  } catch (e: unknown) {
    error.value = e instanceof Error ? e.message : String(e)
  } finally {
    loading.value = false
  }
}

function fmtTs(ts: string) {
  return new Date(ts).toLocaleTimeString('zh-CN', { hour12: false })
}

onMounted(() => {
  load()
  timer = setInterval(load, 5000)
})
onUnmounted(() => {
  if (timer) clearInterval(timer)
})
</script>

<template>
  <div>
    <div class="page-header" style="display:flex;justify-content:space-between;align-items:center;margin-bottom:16px">
      <h2 style="margin:0">路由决策日志</h2>
      <div style="font-size:12px;color:var(--muted)">每 5 秒自动刷新</div>
    </div>

    <!-- Filters -->
    <div class="card" style="margin-bottom:16px;display:flex;gap:16px;flex-wrap:wrap;align-items:center">
      <div style="display:flex;align-items:center;gap:8px;min-width:260px">
        <label style="font-size:13px;white-space:nowrap">模型筛选</label>
        <div style="width:220px">
          <ModelPicker
            v-model="filterModel"
            :allow-free-text="true"
            placeholder="选择或输入模型"
            @update:modelValue="load"
          />
        </div>
      </div>
      <div style="display:flex;align-items:center;gap:8px">
        <label style="font-size:13px;white-space:nowrap">状态</label>
        <select v-model="filterSuccess" @change="load" style="width:100px">
          <option value="">全部</option>
          <option value="true">成功</option>
          <option value="false">失败</option>
        </select>
      </div>
      <div style="display:flex;align-items:center;gap:8px">
        <label style="font-size:13px;white-space:nowrap">最近</label>
        <select v-model="sinceMinutes" @change="load" style="width:100px">
          <option :value="10">10 分钟</option>
          <option :value="30">30 分钟</option>
          <option :value="60">1 小时</option>
          <option :value="360">6 小时</option>
          <option :value="1440">24 小时</option>
        </select>
      </div>
      <div style="display:flex;align-items:center;gap:8px">
        <label style="font-size:13px;white-space:nowrap">条数</label>
        <select v-model="limit" @change="load" style="width:80px">
          <option :value="20">20</option>
          <option :value="50">50</option>
          <option :value="100">100</option>
          <option :value="200">200</option>
        </select>
      </div>
      <button class="btn btn-ghost btn-sm" @click="load">刷新</button>
    </div>

    <div v-if="error" class="error-banner">{{ error }}</div>

    <div class="card" style="overflow:auto">
      <table class="data-table" style="min-width:900px">
        <thead>
          <tr>
            <th>时间</th>
            <th>状态</th>
            <th>模型</th>
            <th>Tier</th>
            <th>延迟</th>
            <th>供应商</th>
            <th>prompt_t</th>
            <th>comp_t</th>
            <th>费用</th>
            <th>错误</th>
          </tr>
        </thead>
        <tbody>
          <tr v-if="!rows.length && !loading">
            <td colspan="10" style="text-align:center;padding:32px;color:var(--muted)">
              暂无决策记录
            </td>
          </tr>
          <tr v-for="r in rows" :key="r.request_id + r.ts" :class="{ 'row-fail': !r.success }">
            <td style="white-space:nowrap;font-size:12px">{{ fmtTs(r.ts) }}</td>
            <td>
              <span :class="r.success ? 'badge-ok' : 'badge-err'">
                {{ r.success ? '✓' : '✗' }}
              </span>
            </td>
            <td style="font-size:12px;max-width:160px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">{{ r.model }}</td>
            <td style="text-align:center">{{ r.tier ?? '—' }}</td>
            <td style="text-align:right">{{ r.latency_ms != null ? r.latency_ms + 'ms' : '—' }}</td>
            <td style="font-size:12px">{{ r.chosen_provider_id ?? '—' }}</td>
            <td style="text-align:right">{{ r.prompt_tokens ?? '—' }}</td>
            <td style="text-align:right">{{ r.completion_tokens ?? '—' }}</td>
            <td style="text-align:right;font-size:12px">
              {{ r.cost_usd != null ? '$' + Number(r.cost_usd).toFixed(5) : '—' }}
            </td>
            <td style="font-size:11px;color:var(--danger);max-width:140px;overflow:hidden;text-overflow:ellipsis">
              {{ r.error_class ?? '' }}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    <div v-if="loading" style="text-align:center;padding:8px;font-size:12px;color:var(--muted)">加载中…</div>
  </div>
</template>

<style scoped>
.data-table { width: 100%; border-collapse: collapse; }
.data-table th {
  text-align: left;
  padding: 8px 12px;
  font-size: 12px;
  color: var(--muted);
  border-bottom: 1px solid var(--border);
  white-space: nowrap;
}
.data-table td {
  padding: 7px 12px;
  border-bottom: 1px solid var(--border);
  vertical-align: middle;
}
.row-fail td { background: rgba(239,68,68,.05); }
.badge-ok  { color: #22c55e; font-weight: 600; }
.badge-err { color: #ef4444; font-weight: 600; }
.error-banner {
  background: rgba(239,68,68,.15);
  border: 1px solid #ef4444;
  border-radius: 8px;
  padding: 12px 16px;
  color: #ef4444;
  margin-bottom: 16px;
}
</style>
