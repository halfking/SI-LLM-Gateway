// useElementSize — track an element's rendered width reactively.
//
// Used by LiveRequestStream to compute how many swim-lane tiles fit
// in the visible track. Each tile is ~52px wide + 4px gap, so a
// 1280px dashboard can show ~22 tiles without horizontal scroll.
// The composable watches the element with ResizeObserver and
// returns a ref that updates on every resize (debounced via the
// browser's own batching — no manual rAF needed).
//
// Why a custom composable instead of `useResizeObserver` from a
// library: the project does not pull vueuse, and this helper is
// 30 lines. Imports would outweigh the benefit.
import { ref, onMounted, onBeforeUnmount, type Ref } from 'vue'

export function useElementSize(target: Ref<HTMLElement | null | undefined>) {
  const width = ref(0)

  let observer: ResizeObserver | null = null

  function update() {
    const el = target.value
    if (!el) return
    const rect = el.getBoundingClientRect()
    width.value = Math.floor(rect.width)
  }

  onMounted(() => {
    update()
    const el = target.value
    if (!el) return
    if (typeof ResizeObserver !== 'undefined') {
      observer = new ResizeObserver(() => update())
      observer.observe(el)
    } else {
      // Fallback: window resize. ResizeObserver is in every browser
      // we target, this branch is for jsdom in tests.
      window.addEventListener('resize', update)
    }
  })

  onBeforeUnmount(() => {
    if (observer) {
      observer.disconnect()
      observer = null
    }
    window.removeEventListener('resize', update)
  })

  return { width }
}