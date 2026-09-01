<script setup>
import { onMounted, onUnmounted, ref } from 'vue'

const currentPage = ref(window.location.hash === '#files' ? 'files' : 'camera')

const status = ref(null)
const error = ref(null)

const exposure = ref(null)
const framerate = ref(null)
const whiteBalance = ref(null)
const saturation = ref(null)
const saturationPosition = ref(0)
const cameraControlBusy = ref(false)
const whiteBalanceBusy = ref(false)
const whiteBalanceError = ref(null)
const saturationBusy = ref(false)
const saturationError = ref(null)
const photoBusy = ref(false)
const photoError = ref(null)
const photoName = ref('microscope')
const aebEnabled = ref(false)
const photoProgress = ref(null)
const lastSavedFiles = ref([])
const shutdownBusy = ref(false)
const shutdownError = ref(null)
const shuttingDown = ref(false)

const files = ref([])
const filesDirectory = ref(null)
const filesBusy = ref(false)
const filesError = ref(null)

const exposureValues = [
  { value: -1, label: '-1' },
  { value: -0.5, label: '-1/2' },
  { value: -0.25, label: '-1/4' },
  { value: 0, label: '0' },
  { value: 0.25, label: '+1/4' },
  { value: 0.5, label: '+1/2' },
  { value: 1, label: '+1' },
]

let exposureTimer = null
let whiteBalanceTimer = null
let photoStatusTimer = null
let saturationTimer = null
let cameraControlVersion = 0
let saturationControlVersion = 0

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

function saturationValueFromPosition(position) {
  if (!saturation.value?.factor) {
    return 1
  }

  return saturation.value.factor ** (Number(position) / 100)
}

function saturationPositionFromValue(value, factor) {
  if (!factor || factor === 1 || value == null) {
    return 0
  }

  return Math.round((Math.log(value) / Math.log(factor)) * 100)
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

function showPage(page) {
  window.location.hash = page === 'files' ? 'files' : ''
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
  photoBusy.value = true
  photoError.value = null
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
        aeb: aebEnabled.value,
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
      throw new Error(`HTTP ${response.status}`)
    }

    return response.json()
  })

  exposure.value = {
    ...exposure.value,
    ...result,
  }
}

async function stepExposure(factor) {
  const result = await runCameraControl(async () => {
    const response = await fetch('/api/exposure/step', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ factor }),
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    return response.json()
  })

  exposure.value = {
    ...exposure.value,
    ...result,
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

  const result = await response.json()
  saturation.value = result
  saturationPosition.value = saturationPositionFromValue(result.value, result.factor)
}

async function setSaturation(position) {
  if (!saturation.value) {
    return
  }

  saturationControlVersion += 1
  const requestVersion = saturationControlVersion
  saturationBusy.value = true
  saturationError.value = null
  const value = saturationValueFromPosition(position)

  try {
    const response = await fetch('/api/saturation', {
      method: 'PUT',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ value }),
    })

    if (!response.ok) {
      throw new Error(await getResponseError(response))
    }

    const result = await response.json()

    if (requestVersion === saturationControlVersion) {
      saturation.value = result
      saturationPosition.value = saturationPositionFromValue(result.value, result.factor)
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

function queueSaturation(event) {
  saturationPosition.value = Number(event.target.value)

  if (saturationTimer) {
    clearTimeout(saturationTimer)
  }

  saturationTimer = setTimeout(() => {
    saturationTimer = null
    setSaturation(saturationPosition.value)
  }, 120)
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
      throw new Error(`HTTP ${response.status}`)
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

async function setWhiteBalanceSingle() {
  whiteBalanceBusy.value = true
  whiteBalanceError.value = null

  try {
    const response = await fetch('/api/whitebalance/single', {
      method: 'POST',
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    whiteBalance.value = await response.json()
  } catch (exc) {
    whiteBalanceError.value = exc.message
  } finally {
    whiteBalanceBusy.value = false
  }
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

  // Bij overgang naar manual houden we expliciet
  // de huidige exposuretijd vast.
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
  if (!window.confirm('Pi volledig uitschakelen?')) {
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
  currentPage.value = window.location.hash === '#files' ? 'files' : 'camera'

  if (currentPage.value === 'files') {
    stopCameraPolling()
    await loadFiles()
    return
  }

  await loadCameraPage()
}

onMounted(async () => {
  window.addEventListener('hashchange', handlePageChange)
  await handlePageChange()
})

onUnmounted(() => {
  window.removeEventListener('hashchange', handlePageChange)
  stopCameraPolling()
  stopPhotoStatusPolling()

  if (saturationTimer) {
    clearTimeout(saturationTimer)
    saturationTimer = null
  }
})
</script>

<template>
  <main v-if="currentPage === 'camera'" id="camera-layout">
    <header id="topbar">
      <nav id="navigation-panel" aria-label="Hoofdnavigatie">
        <button disabled>
          Camera
        </button>
        <button @click="showPage('files')">
          Bestanden
        </button>
        <button
          :disabled="shutdownBusy || shuttingDown"
          @click="shutdownPi"
        >
          {{ shutdownBusy ? 'Pi stoppen...' : 'Stop Pi' }}
        </button>
      </nav>

      <section id="system-status" aria-live="polite">
        <template v-if="shuttingDown">
          <span class="status-primary">Pi wordt afgesloten</span>
          <span class="status-detail">Wacht tot de Pi volledig uit is voordat de voeding wordt losgenomen.</span>
        </template>
        <template v-else-if="shutdownError">
          <span class="status-primary">Afsluitfout</span>
          <span class="status-detail">{{ shutdownError }}</span>
        </template>
        <template v-else-if="error">
          <span class="status-primary">Camerafout</span>
          <span class="status-detail">{{ error }}</span>
        </template>
        <template v-else-if="status">
          <span class="status-primary">Raspicam: {{ status.status }}</span>
          <span class="status-detail">
            {{ status.camera.connected ? 'verbonden' : 'niet verbonden' }}
            <template v-if="status.camera.connected">
              · {{ status.camera.model || 'model onbekend' }}
              · {{ status.camera.hostname || '—' }}
              · {{ status.camera.ip_address || '—' }}
            </template>
          </span>
        </template>
        <template v-else>
          <span class="status-primary">Raspicam</span>
          <span class="status-detail">status ophalen...</span>
        </template>
      </section>
    </header>

    <section id="preview-panel" aria-label="Live preview">
      <img
        src="/api/stream"
        alt="Live camerabeeld"
      >
    </section>

    <aside id="controls-panel" aria-label="Camerainstellingen">
      <section v-if="framerate" id="frame-rate-panel" class="ui-panel">
        <h2>Frame rate</h2>
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
        <p class="compact-info">Huidig: {{ framerate.fps }} fps</p>
      </section>

      <section v-if="exposure" id="exposure-panel" class="ui-panel">
        <h2>Exposure</h2>
        <div class="button-row">
          <button
            :disabled="cameraControlBusy || photoBusy || exposure.auto"
            @click="setExposureAuto(true)"
          >
            Auto
          </button>
          <button
            :disabled="cameraControlBusy || photoBusy || !exposure.auto"
            @click="setExposureAuto(false)"
          >
            Manual
          </button>
        </div>

        <div class="button-row">
          <button
            v-for="item in exposureValues"
            :key="item.value"
            :disabled="cameraControlBusy || photoBusy || !exposure.auto || exposure.exposure_value === item.value"
            @click="setExposureValue(item.value)"
          >
            {{ item.label }}
          </button>
        </div>

        <div class="button-row">
          <button
            :disabled="cameraControlBusy || photoBusy || exposure.auto"
            @click="stepExposure(1 / 4)"
          >
            1/4
          </button>
          <button
            :disabled="cameraControlBusy || photoBusy || exposure.auto"
            @click="stepExposure(1 / 2)"
          >
            1/2
          </button>
          <button
            :disabled="cameraControlBusy || photoBusy || exposure.auto"
            @click="stepExposure(2)"
          >
            2×
          </button>
          <button
            :disabled="cameraControlBusy || photoBusy || exposure.auto"
            @click="stepExposure(4)"
          >
            4×
          </button>
        </div>

        <p class="compact-info">
          {{ formatExposureTime(exposure.exposure_time_us) }} · A {{ formatDigitalGain(exposure.analogue_gain) }} · D {{ formatDigitalGain(exposure.digital_gain) }}
        </p>
      </section>

      <section v-if="whiteBalance" id="white-balance-panel" class="ui-panel">
        <h2>White balance</h2>
        <div class="button-row">
          <button
            :disabled="whiteBalanceBusy || photoBusy || whiteBalance.auto"
            @click="setWhiteBalanceAuto"
          >
            Auto
          </button>
          <button
            :disabled="whiteBalanceBusy || photoBusy"
            @click="setWhiteBalanceSingle"
          >
            {{ whiteBalanceBusy ? 'Meten...' : 'Single' }}
          </button>
        </div>
        <p class="compact-info">
          {{ whiteBalance.auto ? 'Auto' : 'Single' }} · R {{ formatColourGain(whiteBalance.red_gain) }} · B {{ formatColourGain(whiteBalance.blue_gain) }} ·
          {{ whiteBalance.colour_temperature == null ? '—' : `${whiteBalance.colour_temperature} K` }}
        </p>
        <p v-if="whiteBalanceError" class="error-message compact-info">
          Fout: {{ whiteBalanceError }}
        </p>
      </section>

      <section v-if="saturation" id="saturation-panel" class="ui-panel">
        <h2>Verzadiging</h2>
        <input
          :value="saturationPosition"
          :disabled="photoBusy || saturationBusy || shuttingDown"
          type="range"
          min="-100"
          max="100"
          step="1"
          @change="queueSaturation"
        >
        <p class="compact-info">
          {{ formatSaturation(saturationValueFromPosition(saturationPosition)) }}×
          · {{ formatSaturation(saturation.min) }}×–{{ formatSaturation(saturation.max) }}×
          <span v-if="saturationBusy"> · instellen...</span>
        </p>
        <p v-if="saturationError" class="error-message compact-info">
          Fout: {{ saturationError }}
        </p>
      </section>
    </aside>

    <section id="capture-panel" class="ui-panel" aria-label="Foto opnemen">
      <label class="photo-name">
        <span>Foto naam</span>
        <input
          v-model="photoName"
          :disabled="photoBusy"
          type="text"
        >
      </label>

      <div class="capture-mode">
        <span>AEB</span>
        <button
          :disabled="photoBusy || !aebEnabled"
          @click="aebEnabled = false"
        >
          Nee
        </button>
        <button
          :disabled="photoBusy || aebEnabled"
          @click="aebEnabled = true"
        >
          Ja
        </button>
      </div>

      <div class="capture-action">
        <button
          :disabled="photoBusy || !photoName.trim()"
          @click="takePhoto"
        >
          {{ photoBusy ? (aebEnabled ? 'AEB maken...' : 'Foto maken...') : 'Foto nemen' }}
        </button>
      </div>

      <div v-if="photoBusy || lastSavedFiles.length > 0 || photoError" id="capture-feedback">
        <template v-if="photoBusy && photoProgress?.aeb">
          <span>
            AEB opname
            <template v-if="photoProgress.step > 0">
              {{ photoProgress.step }}/{{ photoProgress.total }} {{ formatAebEv(photoProgress.ev) }}
            </template>
          </span>
          <progress
            :value="photoProgress.step"
            :max="photoProgress.total || 3"
          ></progress>
        </template>

        <ul v-if="lastSavedFiles.length > 0" class="compact-info">
          <li
            v-for="filename in lastSavedFiles"
            :key="filename"
          >
            {{ filename }}
          </li>
        </ul>

        <p v-if="photoError" class="error-message compact-info">
          Fout bij foto: {{ photoError }}
        </p>
      </div>
    </section>
  </main>

  <main v-else id="files-layout">
    <nav aria-label="Hoofdnavigatie">
      <button @click="showPage('camera')">
        Camera
      </button>
      <button disabled>
        Bestanden
      </button>
      <button
        :disabled="shutdownBusy || shuttingDown"
        @click="shutdownPi"
      >
        {{ shutdownBusy ? 'Pi stoppen...' : 'Stop Pi' }}
      </button>
    </nav>

    <section class="ui-panel">
      <h2>Bestanden</h2>
      <button
        :disabled="filesBusy"
        @click="loadFiles"
      >
        {{ filesBusy ? 'Verversen...' : 'Verversen' }}
      </button>

      <p v-if="filesDirectory">Map op Pi: {{ filesDirectory }}</p>
      <p v-if="filesError">Fout bij bestanden: {{ filesError }}</p>
      <p v-else-if="!filesBusy && files.length === 0">Nog geen foto's opgeslagen.</p>

      <table v-else-if="files.length > 0">
        <thead>
          <tr>
            <th>Bestand</th>
            <th>Grootte</th>
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
                Download
              </a>
            </td>
          </tr>
        </tbody>
      </table>
    </section>
  </main>
</template>
