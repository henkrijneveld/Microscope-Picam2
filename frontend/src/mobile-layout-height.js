const compactLayoutQuery = window.matchMedia('(max-width: 780px), (max-height: 540px)')

let measureFrame = null
let resizeObserver = null

function scheduleLayoutMeasure() {
  if (measureFrame != null) {
    cancelAnimationFrame(measureFrame)
  }

  measureFrame = requestAnimationFrame(() => {
    measureFrame = null
    measureCameraLayout()
  })
}

function elementBottom(element) {
  if (!element) {
    return Number.NEGATIVE_INFINITY
  }

  let bottom = element.getBoundingClientRect().bottom

  for (const child of element.children) {
    bottom = Math.max(bottom, child.getBoundingClientRect().bottom)
  }

  return bottom
}

function measureCameraLayout() {
  const layout = document.getElementById('camera-layout')

  if (!layout) {
    return
  }

  if (!compactLayoutQuery.matches) {
    layout.style.removeProperty('min-height')
    return
  }

  const layoutRect = layout.getBoundingClientRect()
  const controls = document.getElementById('controls-panel')
  const capture = document.getElementById('capture-panel')
  const preview = document.getElementById('preview-panel')
  const topbar = document.getElementById('topbar')

  const lowestBottom = Math.max(
    elementBottom(topbar),
    elementBottom(preview),
    elementBottom(controls),
    elementBottom(capture),
  )

  const paddingBottom = Number.parseFloat(getComputedStyle(layout).paddingBottom) || 0
  const measuredHeight = Math.ceil(lowestBottom - layoutRect.top + paddingBottom)
  const viewportHeight = Math.ceil(window.visualViewport?.height || window.innerHeight)

  layout.style.minHeight = `${Math.max(viewportHeight, measuredHeight)}px`
}

function refreshResizeObserver() {
  resizeObserver?.disconnect()

  resizeObserver = new ResizeObserver(scheduleLayoutMeasure)

  for (const selector of ['#controls-panel', '#capture-panel', '#preview-panel', '#topbar']) {
    const element = document.querySelector(selector)

    if (element) {
      resizeObserver.observe(element)
    }
  }

  scheduleLayoutMeasure()
}

const app = document.getElementById('app')

if (app) {
  const mutationObserver = new MutationObserver(refreshResizeObserver)
  mutationObserver.observe(app, {
    childList: true,
    subtree: true,
  })
}

window.addEventListener('resize', scheduleLayoutMeasure)
window.visualViewport?.addEventListener('resize', scheduleLayoutMeasure)
compactLayoutQuery.addEventListener('change', scheduleLayoutMeasure)

refreshResizeObserver()
