<script setup lang="ts">
import { useI18n } from 'vue-i18n'
import ModelPicker from './ModelPicker.vue'
import type { CatalogFilterStatusOption } from '../composables/useModelCatalogFilters'

const { t } = useI18n()

withDefaults(defineProps<{
  pickedModel: string
  filterVendor: string
  extraFilter?: string
  textSearch?: string
  vendorOptions: string[]
  count: number
  pickerTitle?: string
  pickerPlaceholder?: string
  vendorLabel?: string
  statusOptions?: CatalogFilterStatusOption[] | null
  statusLabel?: string
  statusSelectClass?: string
  showTextSearch?: boolean
  textSearchPlaceholder?: string
  showClear?: boolean
}>(), {
  extraFilter: '',
  textSearch: '',
  pickerTitle: '',
  pickerPlaceholder: '',
  vendorLabel: '',
  statusOptions: null,
  statusLabel: '',
  statusSelectClass: 'cf-source',
  showTextSearch: false,
  textSearchPlaceholder: '',
  showClear: true,
})

const emit = defineEmits<{
  'update:pickedModel': [value: string]
  'update:filterVendor': [value: string]
  'update:extraFilter': [value: string]
  'update:textSearch': [value: string]
  clear: []
  statusChange: [value: string]
}>()

function onPickedModel(v: string | string[]) {
  emit('update:pickedModel', typeof v === 'string' ? v : (v[0] ?? ''))
}

function onVendor(e: Event) {
  emit('update:filterVendor', (e.target as HTMLSelectElement).value)
}

function onExtra(e: Event) {
  const value = (e.target as HTMLSelectElement).value
  emit('update:extraFilter', value)
  emit('statusChange', value)
}

function onText(e: Event) {
  emit('update:textSearch', (e.target as HTMLInputElement).value)
}
</script>

<template>
  <div class="compact-filter-bar model-catalog-filter-bar">
    <div class="cf-grow" style="min-width:200px">
      <ModelPicker
        :model-value="pickedModel"
        :placeholder="pickerPlaceholder || t('modelCatalogFilterBar.pickerPlaceholder')"
        :title="pickerTitle || t('modelCatalogFilterBar.pickerTitle')"
        @update:model-value="onPickedModel"
      />
    </div>
    <select
      class="cf-select"
      :value="filterVendor"
      @change="onVendor"
    >
      <option value="">{{ vendorLabel || t('modelCatalogFilterBar.vendorLabel') }}</option>
      <option v-for="v in vendorOptions" :key="v" :value="v">{{ v }}</option>
    </select>
    <select
      v-if="statusOptions && statusOptions.length"
      class="cf-select"
      :class="statusSelectClass"
      :value="extraFilter"
      @change="onExtra"
    >
      <option value="">{{ statusLabel || t('modelCatalogFilterBar.statusLabel') }}</option>
      <option v-for="opt in statusOptions" :key="opt.value" :value="opt.value">
        {{ opt.label }}
      </option>
    </select>
    <input
      v-if="showTextSearch"
      class="cf-input cf-grow"
      type="search"
      :value="textSearch"
      :placeholder="textSearchPlaceholder || t('modelCatalogFilterBar.textSearchPlaceholder')"
      @input="onText"
    />
    <button
      v-if="showClear"
      type="button"
      class="btn btn-ghost btn-sm"
      @click="emit('clear')"
    >
      {{ t('modelCatalogFilterBar.clear') }}
    </button>
    <span class="cf-meta">{{ t('modelCatalogFilterBar.count', { count }) }}</span>
  </div>
</template>
