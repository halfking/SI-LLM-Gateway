<template>
  <div class="data-lifecycle-view">
    <div class="page-header">
      <h2 class="page-title">{{ dl('title') }}</h2>
      <div class="header-actions">
        <button class="btn btn-ghost btn-sm" @click="loadStats" :disabled="isLoading">
          {{ isLoading ? dl('loading') : dl('refresh') }}
        </button>
      </div>
    </div>

    <!-- 统计面板 -->
    <div class="stats-row" v-if="stats">
      <div class="stat-card">
        <div class="stat-label">{{ dl('stats.totalData') }}</div>
        <div class="stat-value">{{ formatNumber(stats.total_rows) }}</div>
        <div class="stat-meta">{{ stats.total_size_human }}</div>
      </div>

      <div class="stat-card segment-hot">
        <div class="stat-label">{{ dl('stats.hotData') }}</div>
        <div class="stat-value">{{ formatNumber(stats.hot_data?.rows || 0) }}</div>
        <div class="stat-meta">
          {{ stats.hot_data?.size_human || '0 B' }}
          <span class="stat-percent">({{ (stats.hot_data?.percent_of_total || 0).toFixed(1) }}%)</span>
        </div>
      </div>

      <div class="stat-card segment-warm">
        <div class="stat-label">{{ dl('stats.warmData') }}</div>
        <div class="stat-value">{{ formatNumber(stats.warm_data?.rows || 0) }}</div>
        <div class="stat-meta">
          {{ stats.warm_data?.size_human || '0 B' }}
          <span class="stat-percent">({{ (stats.warm_data?.percent_of_total || 0).toFixed(1) }}%)</span>
        </div>
      </div>

      <div class="stat-card segment-cold">
        <div class="stat-label">{{ dl('stats.coldData') }}</div>
        <div class="stat-value">{{ formatNumber(stats.cold_data?.rows || 0) }}</div>
        <div class="stat-meta">
          {{ stats.cold_data?.size_human || '0 B' }}
          <span class="stat-percent">({{ (stats.cold_data?.percent_of_total || 0).toFixed(1) }}%)</span>
        </div>
      </div>

      <div class="stat-card segment-expired">
        <div class="stat-label">{{ dl('stats.expiredData') }}</div>
        <div class="stat-value">{{ formatNumber(stats.expired_data?.rows || 0) }}</div>
        <div class="stat-meta">
          {{ stats.expired_data?.size_human || '0 B' }}
          <span class="stat-percent">({{ (stats.expired_data?.percent_of_total || 0).toFixed(1) }}%)</span>
        </div>
      </div>
    </div>

    <!-- 数据分布图表 + 增长趋势 -->
    <div class="charts-row" v-if="stats">
      <div class="card chart-card">
        <h3 class="card-title">{{ dl('charts.distribution') }}</h3>
        <div class="chart-container">
          <canvas ref="distributionChart"></canvas>
        </div>
      </div>

      <div class="card trend-card">
        <h3 class="card-title">{{ dl('charts.growthTrend') }}</h3>
        <div class="trend-table-wrap" v-if="stats.growth_trend.length">
          <table class="data-table">
            <thead>
              <tr>
                <th>{{ dl('charts.trendDate') }}</th>
                <th>{{ dl('charts.trendRequests') }}</th>
                <th>{{ dl('charts.trendCompressed') }}</th>
                <th>{{ dl('charts.trendCompressionRate') }}</th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="trend in stats.growth_trend" :key="trend.date">
                <td>{{ trend.date }}</td>
                <td>{{ formatNumber(trend.requests) }}</td>
                <td>{{ formatNumber(trend.compressed) }}</td>
                <td>
                  <span class="rate-badge" :class="{ high: trend.compression_rate > 50 }">
                    {{ trend.compression_rate.toFixed(1) }}%
                  </span>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
        <div v-else class="empty-hint">{{ dl('charts.trendEmpty') }}</div>
      </div>
    </div>

    <!-- 存储管理（磁盘/数据库/附件/日志统计） -->
    <div class="card storage-card">
      <h3 class="card-title">{{ dl('storage.title') }}</h3>

      <div class="storage-loading" v-if="isLoadingStorage">{{ dl('storageLoading') }}</div>

      <template v-else-if="storageStats">
        <!-- 磁盘空间 -->
        <div class="storage-section" v-if="storageStats.disk">
          <div class="section-header">
            <span class="section-title">{{ dl('storage.disk') }}</span>
            <span class="section-path">{{ storageStats.disk.mount_path }}</span>
          </div>
          <div class="disk-bar-track">
            <div
              class="disk-bar-fill"
              :class="{ warning: storageStats.disk.usage_percent > 80, danger: storageStats.disk.usage_percent > 90 }"
              :style="{ width: storageStats.disk.usage_percent + '%' }"
            ></div>
            <span class="disk-bar-text">
              {{ storageStats.disk.used_bytes.toLocaleString() }} / {{ storageStats.disk.total_bytes.toLocaleString() }}
              ({{ storageStats.disk.usage_percent.toFixed(1) }}%)
            </span>
          </div>
        </div>

        <!-- 数据库占用 -->
        <div class="storage-section" v-if="storageStats.database">
          <div class="section-header">
            <span class="section-title">{{ dl('storage.database') }}</span>
            <span class="section-path">{{ dl('storage.databaseTotalSize', { size: storageStats.database.total_size_human }) }}</span>
          </div>
          <div class="table-size-list">
            <div class="table-size-row" v-for="t in storageStats.database.table_sizes" :key="t.table_name">
              <span class="table-name">{{ t.table_name }}</span>
              <span class="table-size">{{ t.size_human }}</span>
              <span class="table-rows" v-if="t.row_count != null">{{ dl('storage.tableRows', { n: t.row_count.toLocaleString() }) }}</span>
            </div>
          </div>
        </div>

        <!-- 附件存储 -->
        <div class="storage-section" v-if="storageStats.attachments_storage">
          <div class="section-header">
            <span class="section-title">{{ dl('storage.attachments') }}</span>
            <span class="section-path">
              {{ storageStats.attachments_storage.storage_path }}
              <span v-if="storageStats.attachments_storage.orphaned_files != null && storageStats.attachments_storage.orphaned_files > 0"
                class="orphan-badge"
                :title="dl('storage.orphanTitle', { n: storageStats.attachments_storage.orphaned_files })">
                {{ dl('storage.orphanBadge', { n: storageStats.attachments_storage.orphaned_files }) }}
              </span>
            </span>
          </div>
          <div class="storage-summary">
            <span>{{ dl('storage.totalFiles', { n: storageStats.attachments_storage.total_files.toLocaleString() }) }}</span>
            <span class="storage-summary-size">{{ storageStats.attachments_storage.total_size_human }}</span>
          </div>
          <div class="media-type-list" v-if="storageStats.attachments_storage.by_media_type.length">
            <div
              class="media-type-row"
              v-for="m in storageStats.attachments_storage.by_media_type"
              :key="m.media_type"
            >
              <span class="media-type-name">{{ m.media_type }}</span>
              <div class="media-type-bar-track">
                <div
                  class="media-type-bar-fill"
                  :style="{
                    width: getMediaTypePercent(m.size_bytes, storageStats.attachments_storage!.total_size_bytes) + '%'
                  }"
                ></div>
              </div>
              <span class="media-type-meta">{{ m.count }} {{ t('common.unit.items') }} · {{ m.size_human }}</span>
            </div>
          </div>
        </div>

        <!-- 日志文件 -->
        <div class="storage-section" v-if="storageStats.log_files_storage">
          <div class="section-header">
            <span class="section-title">{{ dl('storage.logFiles') }}</span>
            <span class="section-path">{{ storageStats.log_files_storage.log_directory }}</span>
          </div>
          <div class="storage-summary">
            <span>{{ dl('storage.totalFiles', { n: storageStats.log_files_storage.total_files }) }}</span>
            <span class="storage-summary-size">{{ storageStats.log_files_storage.total_size_human }}</span>
          </div>
          <div v-if="storageStats.log_files_storage.active_log_file" class="active-log">
            📝 <strong>{{ storageStats.log_files_storage.active_log_file.name }}</strong>
            <span class="active-log-meta">
              {{ dl('storage.activeLabel') }} · {{ storageStats.log_files_storage.active_log_file.size_human }}
            </span>
          </div>
          <div v-if="storageStats.log_files_storage.rotated_files.length" class="rotated-log-list">
            <div
              class="rotated-log-row"
              v-for="r in storageStats.log_files_storage.rotated_files.slice(0, 10)"
              :key="r.path"
            >
              <span class="rotated-name">📦 {{ r.name }}</span>
              <span class="rotated-meta">
                {{ r.size_human }}
                <span v-if="r.is_compressed" class="compressed-badge">.gz</span>
              </span>
            </div>
            <div v-if="storageStats.log_files_storage.rotated_files.length > 10" class="rotated-more">
              {{ dl('storage.moreRotated', { n: storageStats.log_files_storage.rotated_files.length - 10 }) }}
            </div>
          </div>
          <div v-if="storageStats.log_files_storage.config" class="log-config">
            {{ dl('storage.rotation') }}
            {{ dl('storage.rotationSingle', { n: storageStats.log_files_storage.config.max_size_mb }) }} ·
            {{ dl('storage.rotationKeep', { n: storageStats.log_files_storage.config.max_backups }) }} ·
            {{ dl('storage.rotationAge', { n: storageStats.log_files_storage.config.max_age_days }) }} ·
            {{ dl('storage.rotationCompress', { state: storageStats.log_files_storage.config.compress ? dl('storage.rotationYes') : dl('storage.rotationNo') }) }}
          </div>
        </div>

        <!-- 生命周期配置 -->
        <div class="storage-section" v-if="storageStats.lifecycle_config">
          <div class="section-header">
            <span class="section-title">{{ dl('storage.lifecycleConfig') }}</span>
          </div>
          <div class="config-grid">
            <div class="config-row">
              <span class="config-label">{{ dl('storage.configAttachmentPath') }}</span>
              <code class="config-value">{{ storageStats.lifecycle_config.attachment_storage_path }}</code>
            </div>
            <div class="config-row">
              <span class="config-label">{{ dl('storage.configRetention') }}</span>
              <span class="config-value">{{ dl('storage.configRetentionDays', { n: storageStats.lifecycle_config.retention_days }) }}</span>
            </div>
            <div class="config-row">
              <span class="config-label">{{ dl('storage.configMaxAttachment') }}</span>
              <span class="config-value">{{ dl('storage.configMaxAttachmentMb', { n: storageStats.lifecycle_config.max_attachment_size_mb }) }}</span>
            </div>
            <div class="config-row">
              <span class="config-label">{{ dl('storage.configAutoCleanup') }}</span>
              <span class="config-value">{{ storageStats.lifecycle_config.auto_cleanup_enabled ? dl('storage.autoCleanupOn') : dl('storage.autoCleanupOff') }}</span>
            </div>
          </div>
        </div>
      </template>
    </div>

    <!-- 附件清理 -->
    <div class="card cleanup-card" v-if="storageStats">
      <h3 class="card-title">{{ dl('attachmentCleanup.title') }}</h3>
      <div class="cleanup-form">
        <div class="form-row">
          <label class="form-label">{{ dl('attachmentCleanup.mode') }}</label>
          <select v-model="attachmentCleanupMode" class="form-select">
            <option value="old">{{ dl('attachmentCleanup.modeOld') }}</option>
            <option value="orphaned">{{ dl('attachmentCleanup.modeOrphan') }}</option>
          </select>
        </div>
        <div class="form-row" v-if="attachmentCleanupMode === 'old'">
          <label class="form-label">{{ dl('attachmentCleanup.daysLabel') }}</label>
          <input type="number" v-model.number="attachmentCleanupDays" min="7" max="365" class="form-input" />
        </div>
        <div class="form-actions">
          <button class="btn btn-ghost btn-sm" @click="previewAttachmentCleanup" :disabled="isLoading">
            {{ dl('attachmentCleanup.preview') }}
          </button>
          <button class="btn btn-primary btn-sm" @click="executeAttachmentCleanup" :disabled="isLoading || !attachmentCleanupPreview">
            {{ dl('attachmentCleanup.execute') }}
          </button>
        </div>
      </div>
      <div v-if="attachmentCleanupPreview" class="preview-result">
        <div class="preview-item">
          <span class="preview-label">{{ dl('attachmentCleanup.affected') }}</span>
          <span class="preview-value">
            {{ formatNumber(attachmentCleanupPreview.affected_files) }} {{ t('common.unit.items') }}
            <span v-if="attachmentCleanupPreview.orphaned_files">
              {{ dl('attachmentCleanup.orphanedSuffix', { n: attachmentCleanupPreview.orphaned_files }) }}
            </span>
          </span>
        </div>
        <div class="preview-item">
          <span class="preview-label">{{ dl('attachmentCleanup.estimatedFreed') }}</span>
          <span class="preview-value highlight">{{ attachmentCleanupPreview.estimated_freed_human }}</span>
        </div>
        <div v-if="attachmentCleanupPreview.warning_message" class="preview-warning">
          {{ dl('attachmentCleanup.warningPrefix') }} {{ attachmentCleanupPreview.warning_message }}
        </div>
      </div>
    </div>

    <!-- 日志清理 -->
    <div class="card cleanup-card" v-if="storageStats && storageStats.log_files_storage">
      <h3 class="card-title">{{ dl('logCleanup.title') }}</h3>
      <div class="cleanup-form">
        <div class="form-row">
          <label class="form-label">{{ dl('logCleanup.daysLabel') }}</label>
          <input type="number" v-model.number="logCleanupDays" min="7" max="365" class="form-input" />
        </div>
        <div class="form-row">
          <label class="form-label">
            <input type="checkbox" v-model="logCleanupCompressedOnly" />
            {{ dl('logCleanup.compressedOnly') }}
          </label>
        </div>
        <div class="form-actions">
          <button class="btn btn-ghost btn-sm" @click="previewLogCleanup" :disabled="isLoading">
            {{ dl('logCleanup.preview') }}
          </button>
          <button class="btn btn-primary btn-sm" @click="executeLogCleanup" :disabled="isLoading || !logCleanupPreview">
            {{ dl('logCleanup.execute') }}
          </button>
        </div>
      </div>
      <div v-if="logCleanupPreview" class="preview-result">
        <div class="preview-item">
          <span class="preview-label">{{ dl('logCleanup.affected') }}</span>
          <span class="preview-value">{{ formatNumber(logCleanupPreview.affected_files) }} {{ t('common.unit.items') }}</span>
        </div>
        <div class="preview-item">
          <span class="preview-label">{{ dl('logCleanup.estimatedFreed') }}</span>
          <span class="preview-value highlight">{{ logCleanupPreview.estimated_freed_human }}</span>
        </div>
        <div v-if="logCleanupPreview.warning_message" class="preview-warning">
          {{ dl('logCleanup.warningPrefix') }} {{ logCleanupPreview.warning_message }}
        </div>
      </div>
    </div>

    <!-- 数据清理 -->
    <div class="card cleanup-card">
      <h3 class="card-title">{{ dl('dataCleanup.title') }}</h3>

      <div class="cleanup-form">
        <div class="form-row">
          <label class="form-label">{{ dl('dataCleanup.action') }}</label>
          <select v-model="cleanupForm.action" class="form-select">
            <option value="archive">{{ dl('dataCleanup.actionArchive') }}</option>
            <option value="delete">{{ dl('dataCleanup.actionDelete') }}</option>
            <option value="trim">{{ dl('dataCleanup.actionTrim') }}</option>
          </select>
        </div>

        <div class="form-row form-row-dates">
          <div class="date-group">
            <label class="form-label">{{ dl('dataCleanup.from') }}</label>
            <input type="date" v-model="cleanupForm.from" class="form-input" />
          </div>
          <div class="date-group">
            <label class="form-label">{{ dl('dataCleanup.to') }}</label>
            <input type="date" v-model="cleanupForm.to" class="form-input" />
          </div>
        </div>

        <div class="form-actions">
          <button class="btn btn-primary btn-sm" @click="previewCleanup" :disabled="isLoading">
            {{ isLoading ? dl('loading') : dl('dataCleanup.preview') }}
          </button>
          <button class="btn btn-ghost btn-sm" @click="executeCleanup" :disabled="isLoading || !previewResult">
            {{ dl('dataCleanup.execute') }}
          </button>
        </div>
      </div>

      <!-- 预览结果 -->
      <div v-if="previewResult" class="preview-result">
        <div class="preview-item">
          <span class="preview-label">{{ dl('dataCleanup.affected') }}</span>
          <span class="preview-value">{{ formatNumber(previewResult.affected_rows) }} {{ dl('dataCleanup.affectedRowsSuffix') }}</span>
        </div>
        <div class="preview-item">
          <span class="preview-label">{{ dl('dataCleanup.estimatedFreed') }}</span>
          <span class="preview-value highlight">{{ previewResult.estimated_freed_human }}</span>
        </div>
        <div v-if="previewResult.warning_message" class="preview-warning">
          {{ dl('dataCleanup.warningPrefix') }} {{ previewResult.warning_message }}
        </div>
      </div>
    </div>

    <!-- 租户统计（Top 10） -->
    <div class="card tenant-card" v-if="stats && stats.by_tenant.length">
      <h3 class="card-title">{{ dl('tenant.title') }}</h3>
      <div class="tenant-table-wrap">
        <table class="data-table">
          <thead>
            <tr>
              <th>{{ dl('tenant.tenantId') }}</th>
              <th>{{ dl('tenant.rows') }}</th>
              <th>{{ dl('tenant.size') }}</th>
              <th>{{ dl('tenant.percent') }}</th>
            </tr>
          </thead>
          <tbody>
            <tr v-for="tenant in stats.by_tenant" :key="tenant.tenant_id">
              <td><code class="tenant-code">{{ tenant.tenant_id }}</code></td>
              <td>{{ formatNumber(tenant.rows) }}</td>
              <td>{{ tenant.size_human }}</td>
              <td>
                <div class="tenant-bar-track">
                  <div
                    class="tenant-bar-fill"
                    :style="{ width: getTenantPercent(tenant.rows) + '%' }"
                  ></div>
                  <span class="tenant-bar-text">{{ getTenantPercent(tenant.rows).toFixed(1) }}%</span>
                </div>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import { Chart, ChartConfiguration, registerables } from 'chart.js'
import {
  dataLifecycleStats,
  dataLifecycleCleanupPreview,
  getStorageStats,
  cleanupAttachments,
  cleanupLogs,
  type DataLifecycleStatsResponse,
  type DataSegment,
  type TenantDataStats,
  type DailyGrowth,
  type StorageStatsResponse,
  type CleanupAttachmentsResponse,
  type CleanupLogsResponse,
} from '../api'

Chart.register(...registerables)

const { t } = useI18n()
const dl = (k: string, params?: Record<string, unknown>): string =>
  t(`dataLifecycle.${k}` as never, params as never)

interface Stats extends DataLifecycleStatsResponse {}

interface CleanupPreview {
  affected_rows: number
  estimated_freed_bytes: number
  estimated_freed_human: string
  warning_message?: string
}

const stats = ref<Stats | null>(null)
const storageStats = ref<StorageStatsResponse | null>(null)
const isLoadingStorage = ref(false)

const cleanupForm = ref({
  action: 'archive',
  from: '',
  to: '',
})

const previewResult = ref<CleanupPreview | null>(null)
const isLoading = ref(false)
const distributionChart = ref<HTMLCanvasElement | null>(null)
let chartInstance: Chart | null = null

// 附件清理状态
const attachmentCleanupMode = ref<'old' | 'orphaned'>('old')
const attachmentCleanupDays = ref(90)
const attachmentCleanupPreview = ref<CleanupAttachmentsResponse | null>(null)

// 日志清理状态
const logCleanupDays = ref(30)
const logCleanupCompressedOnly = ref(false)
const logCleanupPreview = ref<CleanupLogsResponse | null>(null)

function formatNumber(n: number): string {
  return n.toLocaleString('zh-CN')
}

function getTenantPercent(rows: number): number {
  if (!stats.value || stats.value.total_rows === 0) return 0
  return (rows / stats.value.total_rows) * 100
}

function getMediaTypePercent(size: number, total: number): number {
  if (!total) return 0
  return (size / total) * 100
}

async function loadStats() {
  isLoading.value = true
  isLoadingStorage.value = true
  try {
    const [statsData, storageData] = await Promise.all([
      dataLifecycleStats(),
      getStorageStats().catch((e) => {
        console.warn('storage stats failed:', e)
        return null
      }),
    ])
    stats.value = statsData as Stats
    storageStats.value = storageData

    await nextTick()
    renderChart()
  } catch (error) {
    console.error('Failed to load stats:', error)
  } finally {
    isLoading.value = false
    isLoadingStorage.value = false
  }
}

async function loadStorageStats() {
  isLoadingStorage.value = true
  try {
    storageStats.value = await getStorageStats()
  } catch (error) {
    console.error('storage stats failed:', error)
  } finally {
    isLoadingStorage.value = false
  }
}

function renderChart() {
  if (!distributionChart.value || !stats.value) return

  if (chartInstance) {
    chartInstance.destroy()
  }

  const ctx = distributionChart.value.getContext('2d')
  if (!ctx) return

  const data = [
    stats.value.hot_data?.rows || 0,
    stats.value.warm_data?.rows || 0,
    stats.value.cold_data?.rows || 0,
    stats.value.expired_data?.rows || 0,
  ]

  const config: ChartConfiguration = {
    type: 'doughnut',
    data: {
      labels: [
        dl('chartLabels.hot'),
        dl('chartLabels.warm'),
        dl('chartLabels.cold'),
        dl('chartLabels.expired'),
      ],
      datasets: [
        {
          data,
          backgroundColor: [
            'rgba(52, 211, 153, 0.7)',
            'rgba(251, 191, 36, 0.7)',
            'rgba(96, 165, 250, 0.7)',
            'rgba(248, 113, 113, 0.7)',
          ],
          borderColor: [
            'rgba(52, 211, 153, 1)',
            'rgba(251, 191, 36, 1)',
            'rgba(96, 165, 250, 1)',
            'rgba(248, 113, 113, 1)',
          ],
          borderWidth: 2,
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: {
        legend: {
          position: 'bottom',
          labels: {
            color: '#e6edf3',
            font: { size: 12 },
            padding: 12,
          },
        },
        tooltip: {
          backgroundColor: 'rgba(15, 17, 23, 0.95)',
          titleColor: '#e6edf3',
          bodyColor: '#e6edf3',
          borderColor: 'rgba(99, 102, 241, 0.5)',
          borderWidth: 1,
          callbacks: {
            label: (context) => {
              const label = context.label || ''
              const value = context.parsed
              const total = data.reduce((a, b) => a + b, 0)
              const percentage = total > 0 ? (value / total * 100).toFixed(1) : '0.0'
              return dl('chartLabels.tooltipSuffix', { label, n: formatNumber(value), pct: percentage })
            },
          },
        },
      },
    },
  }

  chartInstance = new Chart(ctx, config)
}

async function previewCleanup() {
  if (!cleanupForm.value.from || !cleanupForm.value.to) {
    alert(dl('dataCleanup.missingDate'))
    return
  }

  isLoading.value = true
  try {
    const result = await dataLifecycleCleanupPreview(
      cleanupForm.value.action,
      cleanupForm.value.from,
      cleanupForm.value.to
    )
    previewResult.value = result
  } catch (error) {
    console.error('Preview failed:', error)
    alert(dl('dataCleanup.previewFailed'))
  } finally {
    isLoading.value = false
  }
}

async function executeCleanup() {
  if (!previewResult.value) {
    alert(dl('dataCleanup.needPreview'))
    return
  }

  const confirmed = confirm(
    cleanupForm.value.action === 'delete'
      ? dl('dataCleanup.confirmDelete', {
          n: formatNumber(previewResult.value.affected_rows),
          size: previewResult.value.estimated_freed_human,
        })
      : dl('dataCleanup.confirmArchive', {
          n: formatNumber(previewResult.value.affected_rows),
          size: previewResult.value.estimated_freed_human,
        })
  )

  if (!confirmed) return

  alert(dl('dataCleanup.executeNotImpl'))
}

// ── 附件清理 ────────────────────────────────────────────────────────
async function previewAttachmentCleanup() {
  if (attachmentCleanupMode.value === 'old' && attachmentCleanupDays.value < 7) {
    alert(dl('attachmentCleanup.minDays'))
    return
  }
  isLoading.value = true
  try {
    const r = await cleanupAttachments({
      dry_run: true,
      older_than_days: attachmentCleanupDays.value,
      orphaned_only: attachmentCleanupMode.value === 'orphaned',
    })
    attachmentCleanupPreview.value = r
  } catch (error) {
    console.error('attachment preview failed:', error)
    alert(dl('attachmentCleanup.previewFailed'))
  } finally {
    isLoading.value = false
  }
}

async function executeAttachmentCleanup() {
  if (!attachmentCleanupPreview.value) return
  const p = attachmentCleanupPreview.value
  const confirmed = confirm(
    dl('attachmentCleanup.confirmTitle', {
      n: formatNumber(p.affected_files),
      size: p.estimated_freed_human,
    })
  )
  if (!confirmed) return
  isLoading.value = true
  try {
    const r = await cleanupAttachments({
      dry_run: false,
      older_than_days: attachmentCleanupDays.value,
      orphaned_only: attachmentCleanupMode.value === 'orphaned',
    })
    attachmentCleanupPreview.value = r
    alert(
      dl('attachmentCleanup.completed', {
        n: r.affected_files,
        db: r.affected_db_rows,
        size: r.estimated_freed_human,
      })
    )
    await loadStorageStats()
  } catch (error) {
    console.error('attachment cleanup failed:', error)
    alert(dl('attachmentCleanup.executeFailed'))
  } finally {
    isLoading.value = false
  }
}

// ── 日志清理 ────────────────────────────────────────────────────────
async function previewLogCleanup() {
  if (logCleanupDays.value < 7) {
    alert(dl('logCleanup.minDays'))
    return
  }
  isLoading.value = true
  try {
    const r = await cleanupLogs({
      dry_run: true,
      older_than_days: logCleanupDays.value,
      compressed_only: logCleanupCompressedOnly.value,
    })
    logCleanupPreview.value = r
  } catch (error) {
    console.error('log preview failed:', error)
    alert(dl('logCleanup.previewFailed'))
  } finally {
    isLoading.value = false
  }
}

async function executeLogCleanup() {
  if (!logCleanupPreview.value) return
  const p = logCleanupPreview.value
  const confirmed = confirm(
    dl('logCleanup.confirmTitle', {
      n: formatNumber(p.affected_files),
      size: p.estimated_freed_human,
    })
  )
  if (!confirmed) return
  isLoading.value = true
  try {
    const r = await cleanupLogs({
      dry_run: false,
      older_than_days: logCleanupDays.value,
      compressed_only: logCleanupCompressedOnly.value,
    })
    logCleanupPreview.value = r
    alert(dl('logCleanup.completed', {
      n: r.affected_files,
      size: r.estimated_freed_human,
    }))
    await loadStorageStats()
  } catch (error) {
    console.error('log cleanup failed:', error)
    alert(dl('logCleanup.executeFailed'))
  } finally {
    isLoading.value = false
  }
}

onMounted(() => {
  loadStats()

  const now = new Date()
  const from = new Date(now.getTime() - 90 * 24 * 60 * 60 * 1000)
  const to = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000)
  cleanupForm.value.from = from.toISOString().split('T')[0]
  cleanupForm.value.to = to.toISOString().split('T')[0]
})
</script>

<style scoped>
.data-lifecycle-view {
  padding: 16px;
  max-width: 1400px;
  margin: 0 auto;
}

.page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 20px;
  flex-wrap: wrap;
  gap: 12px;
}

.page-title {
  margin: 0;
  font-size: 18px;
  font-weight: 600;
  color: var(--text-primary, #e6edf3);
}

.header-actions {
  display: flex;
  gap: 8px;
}

/* ===== 统计卡片 ===== */
.stats-row {
  display: grid;
  grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
  gap: 12px;
  margin-bottom: 16px;
}

.stat-card {
  background: var(--bg-card, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 10px;
  padding: 16px;
  position: relative;
  overflow: hidden;
}

.stat-card::before {
  content: '';
  position: absolute;
  top: 0;
  left: 0;
  width: 3px;
  height: 100%;
  background: var(--text-secondary, #6b7280);
}

.stat-card.segment-hot::before { background: #34d399; }
.stat-card.segment-warm::before { background: #fbbf24; }
.stat-card.segment-cold::before { background: #60a5fa; }
.stat-card.segment-expired::before { background: #f87171; }

.stat-label {
  font-size: 12px;
  color: var(--text-secondary, #8b949e);
  margin-bottom: 6px;
}

.stat-value {
  font-size: 22px;
  font-weight: 700;
  color: var(--text-primary, #e6edf3);
  margin-bottom: 4px;
  font-variant-numeric: tabular-nums;
}

.stat-meta {
  font-size: 11px;
  color: var(--text-secondary, #8b949e);
}

.stat-percent {
  color: var(--text-tertiary, #6b7280);
  margin-left: 4px;
}

/* ===== 卡片通用 ===== */
.card {
  background: var(--bg-card, #161b22);
  border: 1px solid var(--border, #30363d);
  border-radius: 10px;
  padding: 16px;
  margin-bottom: 16px;
}

.card-title {
  margin: 0 0 12px;
  font-size: 14px;
  font-weight: 600;
  color: var(--text-primary, #e6edf3);
  display: flex;
  align-items: center;
  gap: 6px;
}

/* ===== 图表行 ===== */
.charts-row {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 12px;
  margin-bottom: 16px;
}

.chart-card {
  margin-bottom: 0;
}

.chart-container {
  height: 240px;
}

/* ===== 趋势表 ===== */
.trend-table-wrap {
  overflow-x: auto;
}

.data-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 13px;
}

.data-table th {
  text-align: left;
  padding: 8px 10px;
  color: var(--text-secondary, #8b949e);
  font-weight: 500;
  border-bottom: 1px solid var(--border, #30363d);
  white-space: nowrap;
}

.data-table td {
  padding: 8px 10px;
  border-bottom: 1px solid var(--border, #30363d);
  color: var(--text-primary, #e6edf3);
  font-variant-numeric: tabular-nums;
}

.data-table tr:last-child td {
  border-bottom: none;
}

.rate-badge {
  display: inline-block;
  padding: 1px 8px;
  border-radius: 4px;
  background: rgba(99, 102, 241, 0.15);
  color: var(--accent-h, #818cf8);
  font-weight: 500;
}

.rate-badge.high {
  background: rgba(52, 211, 153, 0.15);
  color: #34d399;
}

/* ===== 清理表单 ===== */
.cleanup-form {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.form-row {
  display: flex;
  align-items: center;
  gap: 8px;
  flex-wrap: wrap;
}

.form-row-dates {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}

.date-group {
  display: flex;
  align-items: center;
  gap: 8px;
}

.form-label {
  font-size: 13px;
  color: var(--text-secondary, #8b949e);
  white-space: nowrap;
  min-width: 70px;
}

.form-select, .form-input {
  flex: 1;
  padding: 6px 10px;
  background: var(--bg, #0f1117);
  border: 1px solid var(--border, #30363d);
  border-radius: 6px;
  color: var(--text-primary, #e6edf3);
  font-size: 13px;
}

.form-select:focus, .form-input:focus {
  outline: none;
  border-color: var(--accent, #6366f1);
}

.form-actions {
  display: flex;
  gap: 8px;
  margin-top: 4px;
}

.btn {
  padding: 6px 14px;
  border-radius: 6px;
  border: 1px solid transparent;
  font-size: 13px;
  font-weight: 500;
  cursor: pointer;
  transition: all 0.15s;
}

.btn-sm {
  padding: 4px 10px;
  font-size: 12px;
}

.btn-primary {
  background: var(--accent, #6366f1);
  color: #fff;
}

.btn-primary:hover:not(:disabled) {
  background: var(--accent-h, #818cf8);
}

.btn-ghost {
  background: transparent;
  border-color: var(--border, #30363d);
  color: var(--text-primary, #e6edf3);
}

.btn-ghost:hover:not(:disabled) {
  background: var(--bg-hover, #21262d);
  border-color: var(--text-secondary, #8b949e);
}

.btn:disabled {
  opacity: 0.5;
  cursor: not-allowed;
}

/* ===== 预览结果 ===== */
.preview-result {
  margin-top: 12px;
  padding: 12px;
  background: rgba(99, 102, 241, 0.08);
  border: 1px solid rgba(99, 102, 241, 0.25);
  border-radius: 6px;
}

.preview-item {
  display: flex;
  justify-content: space-between;
  margin-bottom: 6px;
  font-size: 13px;
}

.preview-item:last-child {
  margin-bottom: 0;
}

.preview-label {
  color: var(--text-secondary, #8b949e);
}

.preview-value {
  color: var(--text-primary, #e6edf3);
  font-weight: 500;
  font-variant-numeric: tabular-nums;
}

.preview-value.highlight {
  color: #fbbf24;
  font-weight: 600;
}

.preview-warning {
  margin-top: 8px;
  padding: 6px 10px;
  background: rgba(251, 191, 36, 0.1);
  border-left: 2px solid #fbbf24;
  color: #fbbf24;
  font-size: 12px;
  border-radius: 4px;
}

/* ===== 租户表 ===== */
.tenant-table-wrap {
  overflow-x: auto;
}

.tenant-code {
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 12px;
  padding: 2px 6px;
  background: var(--bg, #0f1117);
  border-radius: 4px;
  color: var(--accent-h, #818cf8);
}

.tenant-bar-track {
  position: relative;
  width: 100%;
  height: 18px;
  background: var(--bg, #0f1117);
  border-radius: 4px;
  overflow: hidden;
}

.tenant-bar-fill {
  position: absolute;
  top: 0;
  left: 0;
  height: 100%;
  background: linear-gradient(90deg, rgba(99, 102, 241, 0.5), rgba(99, 102, 241, 0.8));
  transition: width 0.3s;
}

.tenant-bar-text {
  position: absolute;
  top: 0;
  left: 8px;
  line-height: 18px;
  font-size: 11px;
  color: var(--text-primary, #e6edf3);
  font-weight: 500;
  font-variant-numeric: tabular-nums;
}

/* ===== 空状态 ===== */
.empty-hint {
  text-align: center;
  padding: 32px;
  color: var(--text-secondary, #8b949e);
  font-size: 13px;
}

/* ===== 响应式 ===== */
@media (max-width: 800px) {
  .stats-row {
    grid-template-columns: repeat(2, 1fr);
  }
  .charts-row {
    grid-template-columns: 1fr;
  }
  .form-row-dates {
    grid-template-columns: 1fr;
  }
}

/* ===== 存储管理 ===== */
.storage-loading {
  padding: 16px;
  text-align: center;
  color: var(--text-secondary, #8b949e);
}

.storage-section {
  padding: 10px 0;
  border-bottom: 1px dashed var(--border, #30363d);
}
.storage-section:last-child { border-bottom: none; }

.section-header {
  display: flex;
  justify-content: space-between;
  align-items: baseline;
  margin-bottom: 8px;
  flex-wrap: wrap;
  gap: 6px;
}

.section-title {
  font-size: 13px;
  font-weight: 600;
  color: var(--text-primary, #e6edf3);
}

.section-path {
  font-family: ui-monospace, SFMono-Regular, monospace;
  font-size: 11px;
  color: var(--text-secondary, #8b949e);
  word-break: break-all;
}

.orphan-badge {
  display: inline-block;
  margin-left: 6px;
  padding: 1px 6px;
  background: rgba(251, 191, 36, 0.18);
  color: #fbbf24;
  border-radius: 4px;
  font-size: 11px;
}

.disk-bar-track {
  position: relative;
  width: 100%;
  height: 22px;
  background: var(--bg, #0f1117);
  border-radius: 4px;
  overflow: hidden;
}

.disk-bar-fill {
  position: absolute;
  top: 0;
  left: 0;
  height: 100%;
  background: linear-gradient(90deg, #34d399, #10b981);
  transition: width 0.3s;
}
.disk-bar-fill.warning {
  background: linear-gradient(90deg, #fbbf24, #f59e0b);
}
.disk-bar-fill.danger {
  background: linear-gradient(90deg, #f87171, #ef4444);
}

.disk-bar-text {
  position: absolute;
  top: 0;
  left: 10px;
  line-height: 22px;
  font-size: 12px;
  color: var(--text-primary, #e6edf3);
  font-variant-numeric: tabular-nums;
  font-weight: 500;
}

.table-size-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
}

.table-size-row {
  display: grid;
  grid-template-columns: 1.5fr 1fr 1fr;
  gap: 8px;
  font-size: 12px;
  align-items: center;
}

.table-name {
  font-family: ui-monospace, SFMono-Regular, monospace;
  color: var(--accent-h, #818cf8);
}

.table-size {
  color: var(--text-primary, #e6edf3);
  font-weight: 500;
  font-variant-numeric: tabular-nums;
}

.table-rows {
  color: var(--text-secondary, #8b949e);
  font-variant-numeric: tabular-nums;
}

.storage-summary {
  display: flex;
  gap: 12px;
  font-size: 13px;
  margin-bottom: 6px;
  color: var(--text-primary, #e6edf3);
}

.storage-summary-size {
  font-weight: 600;
  color: var(--accent-h, #818cf8);
}

.media-type-list,
.rotated-log-list {
  display: flex;
  flex-direction: column;
  gap: 4px;
  margin-top: 4px;
}

.media-type-row {
  display: grid;
  grid-template-columns: 100px 1fr 180px;
  gap: 8px;
  font-size: 12px;
  align-items: center;
}

.media-type-name {
  font-family: ui-monospace, SFMono-Regular, monospace;
  color: var(--text-secondary, #8b949e);
}

.media-type-bar-track {
  position: relative;
  height: 14px;
  background: var(--bg, #0f1117);
  border-radius: 3px;
  overflow: hidden;
}

.media-type-bar-fill {
  position: absolute;
  top: 0;
  left: 0;
  height: 100%;
  background: linear-gradient(90deg, rgba(99, 102, 241, 0.5), rgba(99, 102, 241, 0.85));
  transition: width 0.3s;
}

.media-type-meta {
  color: var(--text-primary, #e6edf3);
  font-variant-numeric: tabular-nums;
  text-align: right;
}

.active-log {
  padding: 6px 10px;
  margin-top: 6px;
  background: rgba(96, 165, 250, 0.08);
  border: 1px solid rgba(96, 165, 250, 0.3);
  border-radius: 4px;
  font-size: 12px;
}

.active-log-meta {
  margin-left: 6px;
  color: #60a5fa;
}

.rotated-log-row {
  display: flex;
  justify-content: space-between;
  font-size: 12px;
  padding: 2px 4px;
  font-family: ui-monospace, SFMono-Regular, monospace;
}

.rotated-name {
  color: var(--text-primary, #e6edf3);
}

.rotated-meta {
  color: var(--text-secondary, #8b949e);
  font-variant-numeric: tabular-nums;
}

.compressed-badge {
  display: inline-block;
  margin-left: 4px;
  padding: 0 4px;
  background: rgba(52, 211, 153, 0.18);
  color: #34d399;
  border-radius: 3px;
  font-size: 10px;
}

.rotated-more {
  font-size: 11px;
  color: var(--text-secondary, #8b949e);
  text-align: center;
  padding: 2px 0;
}

.log-config {
  margin-top: 6px;
  padding: 6px 10px;
  background: var(--bg, #0f1117);
  border-radius: 4px;
  font-size: 11px;
  color: var(--text-secondary, #8b949e);
}

.config-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 6px 12px;
}

.config-row {
  display: flex;
  font-size: 12px;
  gap: 6px;
}

.config-label {
  color: var(--text-secondary, #8b949e);
  white-space: nowrap;
}

.config-value {
  color: var(--text-primary, #e6edf3);
  font-weight: 500;
}

@media (max-width: 800px) {
  .media-type-row {
    grid-template-columns: 90px 1fr;
  }
  .media-type-meta {
    grid-column: 1 / -1;
    text-align: left;
  }
  .config-grid {
    grid-template-columns: 1fr;
  }
  .table-size-row {
    grid-template-columns: 1fr 1fr;
  }
}
</style>
