const PREVIEW_ZOOM_LEVELS = [1, 2, 4]

let previewZoom = 1
let panX = 0
let panY = 0
let dragState = null
let attachedPanel = null
let resizeObserver = null

function previewImage(panel) {
  return panel?.querySelector('img') || null
}

function clampPan(panel, image, x, y) {
  if (previewZoom === 1) {
    return { x: 0, y: 0 }
  }

  const style = getComputedStyle(panel)
  const innerWidth = panel.clientWidth
    - parseFloat(style.paddingLeft || '0')
    - parseFloat(style.paddingRight || '0')
  const innerHeight = panel.clientHeight
    - parseFloat(style.paddingTop || '0')
    - parseFloat(style.paddingBottom || '0')

  const maxX = Math.max(0, (image.offsetWidth * previewZoom - innerWidth) / 2)
  const maxY = Math.max(0, (image.offsetHeight * previewZoom - innerHeight) / 2)

  return {
    x: Math.max(-maxX, Math.min(maxX, x)),
    y: Math.max(-maxY, Math.min(maxY, y)),
  }
}

function applyPreviewTransform(panel) {
  const image = previewImage(panel)

  if (!image) {
    return
  }

  const clamped = clampPan(panel, image, panX, panY)
  panX = clamped.x
  panY = clamped.y

  image.style.transform = `translate3d(${panX}px, ${panY}px, 0) scale(${previewZoom})`
  panel.classList.toggle('preview-zoomed', previewZoom > 1)

  for (const button of panel.querySelectorAll('[data-preview-zoom]')) {
    button.setAttribute(
      'aria-pressed',
      String(Number(button.dataset.previewZoom) === previewZoom),
    )
  }
}

function setPreviewZoom(panel, zoom) {
  if (!PREVIEW_ZOOM_LEVELS.includes(zoom)) {
    return
  }

  previewZoom = zoom
  panX = 0
  panY = 0
  dragState = null
  panel.classList.remove('preview-dragging')
  applyPreviewTransform(panel)
}

function createZoomControls(panel) {
  const controls = document.createElement('div')
  controls.className = 'preview-zoom-controls'
  controls.setAttribute('aria-label', 'Preview vergroting')

  for (const zoom of PREVIEW_ZOOM_LEVELS) {
    const button = document.createElement('button')
    button.type = 'button'
    button.textContent = `x${zoom}`
    button.dataset.previewZoom = String(zoom)
    button.setAttribute('aria-pressed', String(zoom === previewZoom))
    button.addEventListener('click', () => setPreviewZoom(panel, zoom))
    controls.appendChild(button)
  }

  panel.appendChild(controls)
}

function startDrag(event, panel, image) {
  if (previewZoom === 1) {
    return
  }

  if (event.pointerType === 'mouse' && event.button !== 0) {
    return
  }

  dragState = {
    pointerId: event.pointerId,
    startX: event.clientX,
    startY: event.clientY,
    originX: panX,
    originY: panY,
  }

  image.setPointerCapture(event.pointerId)
  panel.classList.add('preview-dragging')
  event.preventDefault()
}

function moveDrag(event, panel) {
  if (!dragState || event.pointerId !== dragState.pointerId) {
    return
  }

  panX = dragState.originX + event.clientX - dragState.startX
  panY = dragState.originY + event.clientY - dragState.startY
  applyPreviewTransform(panel)
  event.preventDefault()
}

function stopDrag(event, panel, image) {
  if (!dragState || event.pointerId !== dragState.pointerId) {
    return
  }

  if (image.hasPointerCapture(event.pointerId)) {
    image.releasePointerCapture(event.pointerId)
  }

  dragState = null
  panel.classList.remove('preview-dragging')
}

function attachPreviewZoom() {
  const panel = document.getElementById('preview-panel')

  if (!panel || panel === attachedPanel) {
    return
  }

  const image = previewImage(panel)

  if (!image) {
    return
  }

  attachedPanel = panel
  image.draggable = false

  createZoomControls(panel)

  image.addEventListener('pointerdown', (event) => startDrag(event, panel, image))
  image.addEventListener('pointermove', (event) => moveDrag(event, panel))
  image.addEventListener('pointerup', (event) => stopDrag(event, panel, image))
  image.addEventListener('pointercancel', (event) => stopDrag(event, panel, image))

  resizeObserver?.disconnect()
  resizeObserver = new ResizeObserver(() => applyPreviewTransform(panel))
  resizeObserver.observe(panel)
  resizeObserver.observe(image)

  applyPreviewTransform(panel)
}

const observer = new MutationObserver(attachPreviewZoom)
observer.observe(document.documentElement, {
  childList: true,
  subtree: true,
})

attachPreviewZoom()
