<script setup lang="ts">
import { ref, computed } from 'vue'
import { useI18n } from 'vue-i18n'

const props = withDefaults(defineProps<{
  text: string
  /** wrap = full multiline; ellipsis = single/multi line clamp */
  mode?: 'wrap' | 'ellipsis'
  maxLines?: number
  tag?: 'span' | 'div' | 'h3'
}>(), {
  mode: 'ellipsis',
  maxLines: 1,
  tag: 'span',
})

const { t } = useI18n()

const copied = ref(false)
let copyTimer: ReturnType<typeof setTimeout> | undefined

async function onCopy(evt: MouseEvent) {
  evt.stopPropagation()
  const value = props.text?.trim()
  if (!value) return
  try {
    await navigator.clipboard.writeText(value)
    copied.value = true
    if (copyTimer) clearTimeout(copyTimer)
    copyTimer = setTimeout(() => { copied.value = false }, 1200)
  } catch {
    // ignore
  }
}

const title = computed(() =>
  props.mode === 'ellipsis' && props.text
    ? props.text
    : (copied.value ? t('common.feedback.copied') : t('common.feedback.clickToCopy')),
)
</script>

<template>
  <component
    :is="tag"
    class="copyable-text"
    :class="[mode, { copied }]"
    :title="title"
    :style="mode === 'ellipsis' && maxLines > 1 ? { WebkitLineClamp: String(maxLines) } : undefined"
    @click="onCopy"
  >{{ text }}<span v-if="copied" class="copy-hint">{{ t('common.feedback.copied') }}</span></component>
</template>

<style scoped>
.copyable-text {
  cursor: pointer;
  position: relative;
}
.copyable-text:hover {
  color: var(--accent-h);
}
.copyable-text.wrap {
  white-space: pre-wrap;
  word-break: break-word;
  line-height: 1.5;
}
.copyable-text.ellipsis {
  display: -webkit-box;
  -webkit-box-orient: vertical;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: normal;
  word-break: break-word;
}
.copy-hint {
  margin-left: 6px;
  font-size: 10px;
  color: var(--success);
  font-weight: 600;
}
</style>