import { mount } from '@vue/test-utils'
import { describe, expect, it } from 'vitest'
import { createI18n } from 'vue-i18n'
import { createRouter, createMemoryHistory } from 'vue-router'
import PageBackLink from './PageBackLink.vue'
import zhCN from '../i18n/locales/zh-CN'

// PageBackLink.test.ts — v6.0 audit T11 (2026-06-22, updated 2026-07-02)
//
// Verifies jsdom + @vue/test-utils can mount a real .vue file.
// PageBackLink is a button that calls router.back() or router.push(props.to).
// Updated for audit fix: the default label is now driven by vue-i18n
// (key `common.button.back`) so we install a minimal zh-CN i18n + a
// memory-history router in the test mount.
const i18n = createI18n({
  legacy: false,
  globalInjection: true,
  locale: 'zh-CN',
  messages: { 'zh-CN': zhCN },
})

const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/', name: 'home', component: { template: '<div/>' } }],
})

describe('PageBackLink', () => {
  it('renders a button.page-back with default label "返回"', () => {
    const wrapper = mount(PageBackLink, {
      global: { plugins: [i18n, router] },
    })
    const btn = wrapper.find('button.page-back')
    expect(btn.exists()).toBe(true)
    expect(btn.text()).toContain('返回')
  })

  it('renders the custom label when label prop is set', () => {
    const wrapper = mount(PageBackLink, {
      props: { label: 'back to dashboard' },
      global: { plugins: [i18n, router] },
    })
    expect(wrapper.find('button.page-back').text()).toContain('back to dashboard')
    expect(wrapper.find('button.page-back').text()).not.toContain('返回')
  })
})