<script setup>
import { nextTick, onMounted, onUnmounted, ref } from 'vue'
import NumberStepper from './components/NumberStepper.vue'
import RgbHistogram from './components/RgbHistogram.vue'
import mannetjeUrl from '../mannetje.png'
import { language, setLanguage, t } from './translations.js'

const currentPage = ref(window.location.hash === '#files' ? 'files' : window.location.hash === '#liveview' ? 'liveview' : 'camera')
const liveviewPanel = ref(null)
const liveviewMode = ref('width')
const liveviewOffset = ref({ x: 0, y: 0 })
let liveviewDragStart = null

const status = ref(null)
const error = ref(null)
const previewImage = ref(null)
const pingMs = ref(null)

const exposure = ref(null)
const framerate = ref(null)
const whiteBalance = ref(null)
const rgbSample = ref(null)
const saturation = ref(null)
const cameraControlBusy = ref(false)
const whiteBalanceBusy = ref(false)
const whiteBalanceError = ref(null)
const saturationBusy = ref(false)
const saturationError = ref(null)
const photoBusy = ref(false)
const photoError = ref(null)
const photoName = ref('microscope')
const fovValue = ref('')
const fovUnit = ref('mm')
const captureMode = ref('single')
const photoProgress = ref(null)
const lastSavedFiles = ref([])
const shutdownBusy = ref(false)
const shutdownError = ref(null)
const shuttingDown = ref(false)

const files = ref([])
const filesDirectory = ref(null)
const filesBusy = ref(false)
const filesError = ref(null)

let exposureTimer = null
let whiteBalanceTimer = null
let photoStatusTimer = null
let pingTimer = null
let pingAbortController = null
let pingBusy = false
let cameraControlVersion = 0
let saturationControlVersion = 0

function isHdrMode() {
  return captureMode.value !== 'single'
}

function captureModeLabel(mode = captureMode.value) {
  if (mode === 'hdr3') {
    return 'HDR-3'
  }

  if (mode === 'hdr5') {
    return 'HDR-5'
  }

  return t('capture.single')
}

function formatExposureTime(exposureTimeUs) {
  if (exposureTimeUs == null) {
    return '—'
  }

  if (exposureTimeUs >= 1000) {
    return `${Math.round(exposureTimeUs / 1000)} ms`
  }

  return `${Math.round(exposureTimeUs)} µs`
}

function formatDigitalGain(gain) {
  if (gain == null) {
    return '—'
  }

  return Number(gain).toFixed(1)
}

function formatColourGain(gain) {
  if (gain == null) {
    return '—'
  }

  return Number(gain).toFixed(2)
}

function formatSaturation(value) {
  if (value == null) {
    return '—'
  }

  return Number(value).toFixed(2)
}

function formatFileSize(sizeBytes) {
  if (sizeBytes < 1024 * 1024) {
    return `${Math.round(sizeBytes / 1024)} kB`
  }

  return `${(sizeBytes / (1024 * 1024)).toFixed(1)} MB`
}

function formatAebEv(ev) {
  if (ev == null) {
    return ''
  }

  if (ev > 0) {
    return `+${ev} EV`
  }

  return `${ev} EV`
}

function fileDownloadUrl(filename) {
  return `/api/files/${encodeURIComponent(filename)}`
}

async function openLiveview() {
  window.location.hash = 'liveview'
  await nextTick()
  try {
    await liveviewPanel.value?.requestFullscreen?.()
  } catch (_) {
    // Browsers may deny fullscreen; the full-viewport view still works.
  }
}

async function leaveLiveview() {
  if (document.fullscreenElement) {
    try { await document.exitFullscreen() } catch (_) { /* Return anyway. */ }
  }
  window.location.hash = ''
}

function setLiveviewMode(mode) {
  liveviewMode.value = mode
  liveviewOffset.value = { x: 0, y: 0 }
}

function startLiveviewDrag(event) {
  if (event.button !== 0 || !status.value?.camera?.connected) return
  liveviewDragStart = { x: event.clientX, y: event.clientY, xOffset: liveviewOffset.value.x, yOffset: liveviewOffset.value.y }
  event.currentTarget.setPointerCapture(event.pointerId)
}

function moveLiveviewDrag(event) {
  if (!liveviewDragStart || !liveviewPanel.value) return
  const rect = liveviewPanel.value.getBoundingClientRect()
  const scale = liveviewMode.value === 'width' ? rect.width / 640 : rect.height / 480
  const maxX = Math.max(0, (640 * scale - rect.width) / 2)
  const maxY = Math.max(0, (480 * scale - rect.height) / 2)
  liveviewOffset.value = {
    x: Math.max(-maxX, Math.min(maxX, liveviewDragStart.xOffset + event.clientX - liveviewDragStart.x)),
    y: Math.max(-maxY, Math.min(maxY, liveviewDragStart.yOffset + event.clientY - liveviewDragStart.y)),
  }
}

function endLiveviewDrag() { liveviewDragStart = null }

function showPage(page) {
  window.location.hash = page === 'files' ? 'files' : ''
}

function updateRgbSample(sample) {
  rgbSample.value = sample
}

function parseFovValue() {
  const text = String(fovValue.value).trim().replace(',', '.')

  if (!text) {
    return null
  }

  const value = Number(text)
  return Number.isFinite(value) ? value : null
}

async function measurePing() {
  if (pingBusy || shuttingDown.value || document.hidden) return

  pingBusy = true
  const controller = new AbortController()
  pingAbortController = controller
  const timeout = setTimeout(() => controller.abort(), 3000)
  const start = performance.now()

  try {
    const response = await fetch('/api/ping', {
      cache: 'no-store',
      signal: controller.signal,
    })
    if (!response.ok) throw new Error(`HTTP ${response.status}`)
    pingMs.value = Math.round(performance.now() - start)
  } catch (_) {
    pingMs.value = null
  } finally {
    clearTimeout(timeout)
    if (pingAbortController === controller) pingAbortController = null
    pingBusy = false
  }
}

function startPingPolling() {
  if (pingTimer) return
  measurePing()
  pingTimer = setInterval(measurePing, 1000)
}

function stopPingPolling() {
  if (pingTimer) clearInterval(pingTimer)
  pingTimer = null
  pingAbortController?.abort()
  pingAbortController = null
}

function startCameraPolling() {
  if (!exposureTimer) {
    exposureTimer = setInterval(loadExposure, 500)
  }

  if (!whiteBalanceTimer) {
    whiteBalanceTimer = setInterval(loadWhiteBalance, 1000)
  }
}

function stopCameraPolling() {
  if (exposureTimer) {
    clearInterval(exposureTimer)
    exposureTimer = null
  }

  if (whiteBalanceTimer) {
    clearInterval(whiteBalanceTimer)
    whiteBalanceTimer = null
  }
}

async function loadPhotoStatus() {
  try {
    const response = await fetch('/api/photo/status')

    if (!response.ok) {
      return
    }

    photoProgress.value = await response.json()
  } catch (_) {
    // De opname zelf bepaalt of er werkelijk een fout is.
  }
}

function startPhotoStatusPolling() {
  if (!photoStatusTimer) {
    loadPhotoStatus()
    photoStatusTimer = setInterval(loadPhotoStatus, 250)
  }
}

function stopPhotoStatusPolling() {
  if (photoStatusTimer) {
    clearInterval(photoStatusTimer)
    photoStatusTimer = null
  }
}

async function getResponseError(response) {
  try {
    const result = await response.json()
    return result.detail || `HTTP ${response.status}`
  } catch (_) {
    return `HTTP ${response.status}`
  }
}

async function runCameraControl(action) {
  cameraControlVersion += 1
  cameraControlBusy.value = true

  try {
    return await action()
  } finally {
    cameraControlBusy.value = false
  }
}

async function takePhoto() {
  photoError.value = null
  const fov = parseFovValue()

  if (String(fovValue.value).trim() && (fov == null || fov <= 0)) {
    photoError.value = t('capture.fovPositive')
    return
  }

  photoBusy.value = true
  lastSavedFiles.value = []
  photoProgress.value = null
  startPhotoStatusPolling()

  try {
    const response = await fetch('/api/photo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: photoName.value,
        mode: captureMode.value,
        fov_value: fov,
        fov_unit: fov == null ? null : fovUnit.value,
      }),
    })

    if (!response.ok) {
      throw new Error(await getResponseError(response))
    }

    const result = await response.json()
    lastSavedFiles.value = result.aeb ? result.filenames : [result.filename]
  } catch (exc) {
    photoError.value = exc.message
  } finally {
    stopPhotoStatusPolling()
    photoBusy.value = false
    photoProgress.value = null
    await loadExposure()
    await loadFramerate()
    await loadWhiteBalance()
    await loadSaturation()
  }
}

async function setExposureValue(value) {
  const result = await runCameraControl(async () => {
    const response = await fetch('/api/exposure/value', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ value }),
    })

    if (!response.ok) {
      throw new Error(await getResponseError(response))
    }

    return response.json()
  })

  exposure.value = {
    ...exposure.value,
    ...result,
  }
}

async function setManualExposureTime(valueMs) {
  const exposureTimeUs = Math.max(1, Math.round(Number(valueMs) * 1000))

  const result = await runCameraControl(async () => {
    const response = await fetch('/api/exposure', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        auto: false,
        exposure_time_us: exposureTimeUs,
      }),
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    return response.json()
  })

  exposure.value = {
    ...exposure.value,
    ...result,
    auto: false,
  }
}

async function loadExposure() {
  if (
    currentPage.value !== 'camera'
    || photoBusy.value
    || cameraControlBusy.value
    || shuttingDown.value
    || !status.value?.camera?.connected
  ) {
    return
  }

  const requestVersion = cameraControlVersion
  const response = await fetch('/api/exposure')

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  const result = await response.json()

  if (
    photoBusy.value
    || cameraControlBusy.value
    || shuttingDown.value
    || requestVersion !== cameraControlVersion
  ) {
    return
  }

  exposure.value = result
}

async function loadFramerate() {
  if (
    currentPage.value !== 'camera'
    || photoBusy.value
    || cameraControlBusy.value
    || shuttingDown.value
    || !status.value?.camera?.connected
  ) {
    return
  }

  const response = await fetch('/api/framerate')

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  framerate.value = await response.json()
}

async function loadWhiteBalance() {
  if (
    currentPage.value !== 'camera'
    || photoBusy.value
    || whiteBalanceBusy.value
    || shuttingDown.value
    || !status.value?.camera?.connected
  ) {
    return
  }

  const response = await fetch('/api/whitebalance')

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  whiteBalance.value = await response.json()
}

async function loadSaturation() {
  if (
    currentPage.value !== 'camera'
    || photoBusy.value
    || saturationBusy.value
    || shuttingDown.value
    || !status.value?.camera?.connected
  ) {
    return
  }

  const response = await fetch('/api/saturation')

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  saturation.value = await response.json()
}

async function setSaturation(value) {
  if (!saturation.value) {
    return
  }

  saturationControlVersion += 1
  const requestVersion = saturationControlVersion
  saturationBusy.value = true
  saturationError.value = null
  const nextValue = Number(Number(value).toFixed(2))

  try {
    const response = await fetch('/api/saturation', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ value: nextValue }),
    })

    if (!response.ok) {
      throw new Error(await getResponseError(response))
    }

    const result = await response.json()

    if (requestVersion === saturationControlVersion) {
      saturation.value = result
    }
  } catch (exc) {
    if (requestVersion === saturationControlVersion) {
      saturationError.value = exc.message
    }
  } finally {
    if (requestVersion === saturationControlVersion) {
      saturationBusy.value = false
    }
  }
}

async function loadFiles() {
  filesBusy.value = true
  filesError.value = null

  try {
    const response = await fetch('/api/files')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    const result = await response.json()
    files.value = result.files
    filesDirectory.value = result.directory
  } catch (exc) {
    filesError.value = exc.message
  } finally {
    filesBusy.value = false
  }
}

async function setWhiteBalanceAuto() {
  whiteBalanceBusy.value = true
  whiteBalanceError.value = null

  try {
    const response = await fetch('/api/whitebalance', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ auto: true }),
    })

    if (!response.ok) {
      throw new Error(await getResponseError(response))
    }

    const result = await response.json()
    whiteBalance.value = {
      ...whiteBalance.value,
      ...result,
    }
  } catch (exc) {
    whiteBalanceError.value = exc.message
  } finally {
    whiteBalanceBusy.value = false
  }
}

async function setWhiteBalanceManual() {
  whiteBalanceBusy.value = true
  whiteBalanceError.value = null

  try {
    const response = await fetch('/api/whitebalance/single', {
      method: 'POST',
    })

    if (!response.ok) {
      throw new Error(await getResponseError(response))
    }

    whiteBalance.value = await response.json()
  } catch (exc) {
    whiteBalanceError.value = exc.message
  } finally {
    whiteBalanceBusy.value = false
  }
}

async function setWhiteBalanceGains(redGain, blueGain) {
  if (redGain == null || blueGain == null) {
    return
  }

  whiteBalanceBusy.value = true
  whiteBalanceError.value = null

  try {
    const response = await fetch('/api/whitebalance/gains', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        red_gain: Number(Number(redGain).toFixed(2)),
        blue_gain: Number(Number(blueGain).toFixed(2)),
      }),
    })

    if (!response.ok) {
      throw new Error(await getResponseError(response))
    }

    whiteBalance.value = await response.json()
  } catch (exc) {
    whiteBalanceError.value = exc.message
  } finally {
    whiteBalanceBusy.value = false
  }
}

async function setWhiteBalanceFromSample() {
  whiteBalanceError.value = null

  const sample = rgbSample.value
  const currentRed = Number(whiteBalance.value?.red_gain)
  const currentBlue = Number(whiteBalance.value?.blue_gain)

  if (
    !sample
    || !Number.isFinite(currentRed)
    || !Number.isFinite(currentBlue)
    || !Number.isFinite(sample.red)
    || !Number.isFinite(sample.green)
    || !Number.isFinite(sample.blue)
    || sample.red <= 0
    || sample.green <= 0
    || sample.blue <= 0
  ) {
    whiteBalanceError.value = t('whiteBalance.noRgbSample')
    return
  }

  const nextRed = Math.max(0.01, Math.min(32, currentRed * sample.green / sample.red))
  const nextBlue = Math.max(0.01, Math.min(32, currentBlue * sample.green / sample.blue))

  await setWhiteBalanceGains(nextRed, nextBlue)
}

function setWhiteBalanceRedGain(value) {
  setWhiteBalanceGains(value, whiteBalance.value?.blue_gain)
}

function setWhiteBalanceBlueGain(value) {
  setWhiteBalanceGains(whiteBalance.value?.red_gain, value)
}

async function setFramerate(fps) {
  const result = await runCameraControl(async () => {
    const response = await fetch('/api/framerate', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ fps }),
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    return response.json()
  })

  framerate.value = result
}

async function setExposureAuto(auto) {
  const body = {
    auto,
  }

  if (!auto && exposure.value?.exposure_time_us) {
    body.exposure_time_us = exposure.value.exposure_time_us
  }

  const result = await runCameraControl(async () => {
    const response = await fetch('/api/exposure', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(body),
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    return response.json()
  })

  const nextExposure = {
    ...exposure.value,
    auto: result.auto,
    exposure_value: result.exposure_value,
  }

  if (result.exposure_time_us != null) {
    nextExposure.exposure_time_us = result.exposure_time_us
  }

  exposure.value = nextExposure
}

async function shutdownPi() {
  if (!window.confirm(t('confirm.shutdown'))) {
    return
  }

  shutdownBusy.value = true
  shutdownError.value = null
  stopCameraPolling()

  try {
    const response = await fetch('/api/system/shutdown', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        confirm: 'shutdown',
      }),
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    shuttingDown.value = true
  } catch (exc) {
    shutdownError.value = exc.message
    startCameraPolling()
  } finally {
    shutdownBusy.value = false
  }
}

async function loadCameraPage() {
  error.value = null

  try {
    const response = await fetch('/api/status')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    status.value = await response.json()

    if (status.value.camera.connected) {
      await loadExposure()
      await loadFramerate()
      await loadWhiteBalance()
      await loadSaturation()
      startCameraPolling()
    }
  } catch (exc) {
    error.value = exc.message
  }
}

async function handlePageChange() {
  currentPage.value = window.location.hash === '#files' ? 'files' : window.location.hash === '#liveview' ? 'liveview' : 'camera'

  if (currentPage.value === 'liveview') {
    stopCameraPolling()
    if (!status.value) await loadCameraPage()
    return
  }

  if (currentPage.value === 'files') {
    stopCameraPolling()
    await loadFiles()
    return
  }

  await loadCameraPage()
}

onMounted(async () => {
  window.addEventListener('hashchange', handlePageChange)
  startPingPolling()
  await handlePageChange()
})

onUnmounted(() => {
  window.removeEventListener('hashchange', handlePageChange)
  stopCameraPolling()
  stopPhotoStatusPolling()
  stopPingPolling()
})
</script>

<template>
  <section v-if="currentPage === 'liveview'" ref="liveviewPanel" id="liveview-panel" :aria-label="t('navigation.liveview')">
    <div class="liveview-image-area"
      @pointerdown="startLiveviewDrag" @pointermove="moveLiveviewDrag"
      @pointerup="endLiveviewDrag" @pointercancel="endLiveviewDrag" @lostpointercapture="endLiveviewDrag">
      <img v-if="status?.camera?.connected" class="liveview-image"
        :class="'liveview-' + liveviewMode"
        :style="{ transform: 'translate(calc(-50% + ' + liveviewOffset.x + 'px), calc(-50% + ' + liveviewOffset.y + 'px))' }"
        :src="'/api/stream'" :alt="t('aria.liveCameraImage')" draggable="false">
      <p v-else class="liveview-error">{{ status?.camera?.error || t('status.cameraNotConnected') }}</p>
    </div>
    <div class="liveview-actions">
      <button :disabled="liveviewMode === 'width'" @click="setLiveviewMode('width')">{{ t('liveview.width') }}</button>
      <button :disabled="liveviewMode === 'height'" @click="setLiveviewMode('height')">{{ t('liveview.height') }}</button>
      <button @click="leaveLiveview">{{ t('liveview.back') }}</button>
      <span class="liveview-fullscreen-hint">{{ t('liveview.fullscreenHint') }}</span>
    </div>
    <span class="liveview-ping" :title="t('status.pingHint')">
      {{ t('status.ping') }}: {{ pingMs === null ? '—' : `${pingMs} ms` }}
    </span>
  </section>
  <main v-else-if="currentPage === 'camera'" id="camera-layout">
    <header id="topbar">
      <nav id="navigation-panel" :aria-label="t('aria.mainNavigation')">
        <button disabled>
          {{ t('navigation.camera') }}
        </button>
        <button @click="openLiveview">{{ t('navigation.liveview') }}</button>
        <button @click="showPage('files')">
          {{ t('navigation.files') }}
        </button>
        <button
          :disabled="shutdownBusy || shuttingDown"
          @click="shutdownPi"
        >
          {{ shutdownBusy ? t('navigation.stoppingPi') : t('navigation.stopPi') }}
        </button>
      </nav>

      <section id="system-status" aria-live="polite">
        <template v-if="shuttingDown">
          <span class="status-primary">{{ t('status.shuttingDown') }}</span>
          <span class="status-detail">{{ t('status.shutdownWait') }}</span>
        </template>
        <template v-else-if="shutdownError">
          <span class="status-primary">{{ t('status.shutdownError') }}</span>
          <span class="status-detail">{{ shutdownError }}</span>
        </template>
        <template v-else-if="error">
          <span class="status-primary">{{ t('status.cameraError') }}</span>
          <span class="status-detail">{{ error }}</span>
        </template>
        <template v-else-if="status">
          <span class="status-primary">MicroRasp: {{ status.status }}</span>
          <span class="status-detail">
            <template v-if="!status.camera.connected">
              {{ t('common.notConnected') }}
              <template v-if="status.camera.error"> · {{ status.camera.error }}</template>
            </template>
            <template v-else>
              {{ status.camera.model || t('common.unknownModel') }}
              · {{ status.camera.hostname || '—' }}
              · {{ status.camera.ip_address || '—' }}
            </template>
          </span>
        </template>
        <template v-else>
          <span class="status-primary">MicroRasp</span>
          <span class="status-detail">{{ t('common.loadingStatus') }}</span>
        </template>
        <span v-if="!shuttingDown" class="status-ping" :title="t('status.pingHint')">
          {{ t('status.ping') }}: {{ pingMs === null ? '—' : `${pingMs} ms` }}
        </span>
      </section>

      <div class="topbar-actions">
        <div class="language-switch" role="group" :aria-label="t('aria.language')">
          <button type="button" :disabled="language === 'nl'" @click="setLanguage('nl')">NL</button>
          <button type="button" :disabled="language === 'en'" @click="setLanguage('en')">EN</button>
        </div>

        <img
          class="app-logo"
          :src="mannetjeUrl"
          alt="MicroRasp"
        >
      </div>
    </header>

    <section id="preview-panel" :aria-label="t('aria.livePreview')">
      <img
        v-if="status?.camera?.connected"
        ref="previewImage"
        :src="'/api/stream'"
        :alt="t('aria.liveCameraImage')"
      >
      <p v-else-if="status && !status.camera.connected">
        {{ t('status.cameraNotConnected') }}<template v-if="status.camera.error"> · {{ status.camera.error }}</template>
      </p>
    </section>

    <aside id="controls-panel" :aria-label="t('aria.cameraSettings')">
      <section v-if="framerate" id="frame-rate-panel" class="ui-panel">
        <h2>{{ t('frameRate.title') }}</h2>
        <div class="button-row">
          <button
            v-for="fps in framerate.options"
            :key="fps"
            :disabled="cameraControlBusy || photoBusy || framerate.fps === fps"
            @click="setFramerate(fps)"
          >
            {{ fps }} fps
          </button>
        </div>
        <p class="compact-info">{{ t('frameRate.current') }}: {{ framerate.fps }} fps</p>
      </section>

      <section v-if="exposure" id="exposure-panel" class="ui-panel">
        <h2>{{ t('exposure.title') }}</h2>
        <div class="button-row">
          <button
            :disabled="cameraControlBusy || photoBusy || exposure.auto"
            @click="setExposureAuto(true)"
          >
            {{ t('common.auto') }}
          </button>
          <button
            :disabled="cameraControlBusy || photoBusy || !exposure.auto"
            @click="setExposureAuto(false)"
          >
            {{ t('common.manual') }}
          </button>
        </div>

        <NumberStepper
          :model-value="exposure.exposure_value ?? 0"
          :step="0.25"
          :inner-step="0.25"
          :outer-step="exposure.aeb_stops ?? 1"
          :min="exposure.exposure_value_min ?? -2"
          :max="exposure.exposure_value_max ?? 2"
          suffix="EV"
          :disabled="cameraControlBusy || photoBusy || !exposure.auto"
          @commit="setExposureValue"
        />

        <NumberStepper
          :model-value="exposure.exposure_time_us == null ? 0 : exposure.exposure_time_us / 1000"
          :step="1"
          :min="0.001"
          suffix="ms"
          :disabled="cameraControlBusy || photoBusy || exposure.auto"
          @commit="setManualExposureTime"
        />

        <p class="compact-info">
          {{ formatExposureTime(exposure.exposure_time_us) }} · {{ t('exposure.analogue') }} {{ formatDigitalGain(exposure.analogue_gain) }} · {{ t('exposure.digital') }} {{ formatDigitalGain(exposure.digital_gain) }}
        </p>
      </section>

      <section v-if="whiteBalance" id="white-balance-panel" class="ui-panel">
        <h2>{{ t('whiteBalance.title') }}</h2>
        <div class="button-row">
          <button
            :disabled="whiteBalanceBusy || photoBusy || whiteBalance.auto"
            @click="setWhiteBalanceAuto"
          >
            {{ t('common.auto') }}
          </button>
          <button
            :disabled="whiteBalanceBusy || photoBusy"
            @click="setWhiteBalanceManual"
          >
            {{ whiteBalanceBusy ? t('whiteBalance.measuring') : t('common.manual') }}
          </button>
          <button
            :disabled="whiteBalanceBusy || photoBusy || !rgbSample"
            @click="setWhiteBalanceFromSample"
          >
            SetWB
          </button>
        </div>
        <p class="compact-info">
          {{ whiteBalance.auto ? t('common.auto') : t('common.manual') }} · {{ t('whiteBalance.red') }} {{ formatColourGain(whiteBalance.red_gain) }} · {{ t('whiteBalance.blue') }} {{ formatColourGain(whiteBalance.blue_gain) }} ·
          {{ whiteBalance.colour_temperature == null ? '—' : `${whiteBalance.colour_temperature} K` }}
        </p>
        <p v-if="whiteBalanceError" class="error-message compact-info">
          {{ t('common.error') }}: {{ whiteBalanceError }}
        </p>
        <RgbHistogram
          :source-element="previewImage"
          :interval-ms="500"
          @sample="updateRgbSample"
        />
        <div class="white-balance-adjustments">
          <div class="white-balance-adjustment">
            <span>{{ t('whiteBalance.red') }}</span>
            <NumberStepper
              :model-value="whiteBalance.red_gain ?? 1"
              :step="0.01"
              :min="0.01"
              :max="32"
              :disabled="whiteBalanceBusy || photoBusy || whiteBalance.auto"
              @commit="setWhiteBalanceRedGain"
            />
          </div>
          <div class="white-balance-adjustment">
            <span>{{ t('whiteBalance.blue') }}</span>
            <NumberStepper
              :model-value="whiteBalance.blue_gain ?? 1"
              :step="0.01"
              :min="0.01"
              :max="32"
              :disabled="whiteBalanceBusy || photoBusy || whiteBalance.auto"
              @commit="setWhiteBalanceBlueGain"
            />
          </div>
        </div>
      </section>

      <section v-if="saturation" id="saturation-panel" class="ui-panel">
        <h2>{{ t('saturation.title') }}</h2>
        <NumberStepper
          :model-value="saturation.value"
          :step="0.01"
          :min="saturation.min"
          :max="saturation.max"
          suffix="×"
          :disabled="photoBusy || saturationBusy || shuttingDown"
          @commit="setSaturation"
        />
        <p class="compact-info">
          {{ t('saturation.range') }}: {{ formatSaturation(saturation.min) }}×–{{ formatSaturation(saturation.max) }}×
          <span v-if="saturationBusy"> · {{ t('saturation.setting') }}</span>
        </p>
        <p v-if="saturationError" class="error-message compact-info">
          {{ t('common.error') }}: {{ saturationError }}
        </p>
      </section>
    </aside>

    <section id="capture-panel" class="ui-panel" :aria-label="t('aria.capturePhoto')">
      <label class="photo-name">
        <span>{{ t('capture.photoName') }}</span>
        <input
          v-model="photoName"
          :disabled="photoBusy"
          type="text"
        >
      </label>

      <div class="capture-mode">
        <span>{{ t('capture.mode') }}</span>
        <button
          :disabled="photoBusy || captureMode === 'single'"
          @click="captureMode = 'single'"
        >
          {{ t('capture.single') }}
        </button>
        <button
          :disabled="photoBusy || captureMode === 'hdr3'"
          @click="captureMode = 'hdr3'"
        >
          HDR-3
        </button>
        <button
          :disabled="photoBusy || captureMode === 'hdr5'"
          @click="captureMode = 'hdr5'"
        >
          HDR-5
        </button>
      </div>

      <div class="capture-action">
        <button
          :disabled="photoBusy || !photoName.trim()"
          @click="takePhoto"
        >
          {{ photoBusy ? (isHdrMode() ? t('capture.takingMode', { mode: captureModeLabel() }) : t('capture.taking')) : t('capture.takePhoto') }}
        </button>
      </div>

      <div class="fov-setting">
        <span>FOV</span>
        <input
          v-model="fovValue"
          :disabled="photoBusy"
          type="text"
          inputmode="decimal"
          :placeholder="t('capture.fovPlaceholder')"
          :aria-label="t('aria.fov')"
        >
        <button
          :disabled="photoBusy || fovUnit === 'µm'"
          type="button"
          @click="fovUnit = 'µm'"
        >
          µm
        </button>
        <button
          :disabled="photoBusy || fovUnit === 'mm'"
          type="button"
          @click="fovUnit = 'mm'"
        >
          mm
        </button>
        <button
          :disabled="photoBusy || fovUnit === 'cm'"
          type="button"
          @click="fovUnit = 'cm'"
        >
          cm
        </button>
      </div>

      <div
        id="capture-feedback"
        aria-live="polite"
        :style="{ gridTemplateColumns: photoBusy && isHdrMode() ? '82px minmax(0, 1fr)' : 'minmax(0, 1fr)' }"
      >
        <div
          v-show="photoBusy && isHdrMode()"
          class="capture-progress"
          :class="{ visible: photoBusy && isHdrMode() }"
          :style="{ gridTemplateColumns: `repeat(${photoProgress?.total || (captureMode === 'hdr5' ? 5 : 3)}, 1fr)` }"
          aria-hidden="true"
        >
          <span
            v-for="step in (photoProgress?.total || (captureMode === 'hdr5' ? 5 : 3))"
            :key="step"
            class="capture-progress-block"
            :class="{ complete: photoProgress?.aeb && photoProgress.step >= step }"
          ></span>
        </div>

        <span
          v-if="photoError"
          id="capture-status-text"
          class="error-message"
        >
          {{ t('common.error') }}: {{ photoError }}
        </span>
        <span
          v-else-if="photoBusy && photoProgress?.aeb"
          id="capture-status-text"
        >
          {{ t('capture.captureMode', { mode: captureModeLabel(photoProgress.mode) }) }}
          <template v-if="photoProgress.step > 0">
            {{ photoProgress.step }}/{{ photoProgress.total }} · {{ formatAebEv(photoProgress.ev) }}
          </template>
        </span>
        <span
          v-else-if="photoBusy"
          id="capture-status-text"
        >
          {{ t('capture.making') }}
        </span>
        <span
          v-else-if="lastSavedFiles.length > 0"
          id="capture-status-text"
          :title="lastSavedFiles.join(' · ')"
        >
          <strong>{{ t('capture.saved') }}</strong> {{ lastSavedFiles.join(' · ') }}
        </span>
        <span
          v-else
          id="capture-status-text"
        >
          <strong>{{ t('capture.ready') }}</strong>
        </span>
      </div>
    </section>
  </main>

  <main v-else id="files-layout">
    <nav :aria-label="t('aria.mainNavigation')">
      <button @click="showPage('camera')">
        Camera
      </button>
      <button disabled>
        {{ t('navigation.files') }}
      </button>
      <button
        :disabled="shutdownBusy || shuttingDown"
        @click="shutdownPi"
      >
        {{ shutdownBusy ? t('navigation.stoppingPi') : t('navigation.stopPi') }}
      </button>
    </nav>

    <div class="topbar-actions">
      <div class="language-switch" role="group" :aria-label="t('aria.language')">
        <button type="button" :disabled="language === 'nl'" @click="setLanguage('nl')">NL</button>
        <button type="button" :disabled="language === 'en'" @click="setLanguage('en')">EN</button>
      </div>

      <img
        class="app-logo"
        :src="mannetjeUrl"
        alt="MicroRasp"
      >
    </div>

    <section class="ui-panel">
      <h2>{{ t('files.title') }}</h2>
      <button
        :disabled="filesBusy"
        @click="loadFiles"
      >
        {{ filesBusy ? t('common.refreshing') : t('common.refresh') }}
      </button>

      <p v-if="filesDirectory">{{ t('files.folder') }} {{ filesDirectory }}</p>
      <p v-if="filesError">{{ t('files.error') }} {{ filesError }}</p>
      <p v-else-if="!filesBusy && files.length === 0">{{ t('files.none') }}</p>

      <table v-else-if="files.length > 0">
        <thead>
          <tr>
            <th>{{ t('files.file') }}</th>
            <th>{{ t('files.size') }}</th>
            <th></th>
          </tr>
        </thead>
        <tbody>
          <tr
            v-for="file in files"
            :key="file.name"
          >
            <td>{{ file.name }}</td>
            <td>{{ formatFileSize(file.size_bytes) }}</td>
            <td>
              <a
                :href="fileDownloadUrl(file.name)"
                :download="file.name"
              >
                {{ t('common.download') }}
              </a>
            </td>
          </tr>
        </tbody>
      </table>
    </section>
  </main>
</template>
