<script setup>
import { onMounted, onUnmounted, ref } from 'vue'

const status = ref(null)
const error = ref(null)

const exposure = ref(null)
const framerate = ref(null)
const whiteBalance = ref(null)
const whiteBalanceBusy = ref(false)
const whiteBalanceError = ref(null)
const photoBusy = ref(false)
const photoError = ref(null)
const photoName = ref('microscope')

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

function getDownloadFilename(response) {
  const contentDisposition = response.headers.get('Content-Disposition')
  const match = contentDisposition?.match(/filename="([^"]+)"/)

  return match?.[1] ?? 'microscope.jpg'
}

async function takePhoto() {
  photoBusy.value = true
  photoError.value = null

  try {
    const response = await fetch('/api/photo', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: photoName.value,
      }),
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    const filename = getDownloadFilename(response)
    const blob = await response.blob()
    const url = URL.createObjectURL(blob)
    const link = document.createElement('a')

    link.href = url
    link.download = filename
    document.body.appendChild(link)
    link.click()
    link.remove()

    URL.revokeObjectURL(url)
  } catch (exc) {
    photoError.value = exc.message
  } finally {
    photoBusy.value = false
    await loadExposure()
    await loadFramerate()
    await loadWhiteBalance()
  }
}

async function setExposureValue(value) {
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

  await loadExposure()
}

async function stepExposure(factor) {
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

  // De poll leest daarna de werkelijk toegepaste camerawaarde terug.
}

async function loadExposure() {
  if (photoBusy.value) {
    return
  }

  const response = await fetch('/api/exposure')

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  exposure.value = await response.json()
}

async function loadFramerate() {
  const response = await fetch('/api/framerate')

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  framerate.value = await response.json()
}

async function loadWhiteBalance() {
  if (photoBusy.value || whiteBalanceBusy.value) {
    return
  }

  const response = await fetch('/api/whitebalance')

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  whiteBalance.value = await response.json()
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
  } catch (exc) {
    whiteBalanceError.value = exc.message
  } finally {
    whiteBalanceBusy.value = false
    await loadWhiteBalance()
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
    await loadWhiteBalance()
  }
}

async function setFramerate(fps) {
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

  await loadFramerate()
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

  await loadExposure()
}

onMounted(async () => {
  try {
    const response = await fetch('/api/status')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    status.value = await response.json()

    await loadExposure()
    await loadFramerate()
    await loadWhiteBalance()

    exposureTimer = setInterval(loadExposure, 500)
    whiteBalanceTimer = setInterval(loadWhiteBalance, 1000)
  } catch (exc) {
    error.value = exc.message
  }
})

onUnmounted(() => {
  if (exposureTimer) {
    clearInterval(exposureTimer)
  }

  if (whiteBalanceTimer) {
    clearInterval(whiteBalanceTimer)
  }
})
</script>

<template>
  <main>
    <h1>Microscope Picam2</h1>

    <p v-if="error">
      Fout: {{ error }}
    </p>

    <div v-else-if="status">
      <p>Status: {{ status.status }}</p>
      <p>Camera connected: {{ status.camera.connected }}</p>
      <p>Model: {{ status.camera.model }}</p>
    </div>

    <p v-else>
      Camerastatus ophalen...
    </p>

    <section v-if="framerate">
      <h2>Frame rate</h2>

      <button
        v-for="fps in framerate.options"
        :key="fps"
        :disabled="framerate.fps === fps"
        @click="setFramerate(fps)"
      >
        {{ fps }} fps
      </button>

      <p>
        Huidig: {{ framerate.fps }} fps
      </p>
    </section>

    <section v-if="exposure">
      <h2>Exposure</h2>

      <button
        :disabled="exposure.auto"
        @click="setExposureAuto(true)"
      >
        Auto
      </button>

      <button
        :disabled="!exposure.auto"
        @click="setExposureAuto(false)"
      >
        Manual
      </button>

      <div>
        <button
          v-for="item in exposureValues"
          :key="item.value"
          :disabled="!exposure.auto || exposure.exposure_value === item.value"
          @click="setExposureValue(item.value)"
        >
          {{ item.label }}
        </button>
      </div>

      <div>
        <button
          :disabled="exposure.auto"
          @click="stepExposure(1 / 4)"
        >
          1/4
        </button>

        <button
          :disabled="exposure.auto"
          @click="stepExposure(1 / 2)"
        >
          1/2
        </button>

        <button
          :disabled="exposure.auto"
          @click="stepExposure(2)"
        >
          2×
        </button>

        <button
          :disabled="exposure.auto"
          @click="stepExposure(4)"
        >
          4×
        </button>
      </div>

      <p>
        Exposure: {{ formatExposureTime(exposure.exposure_time_us) }}<br>
        Analogue gain: {{ formatDigitalGain(exposure.analogue_gain) }}<br>
        Digital gain: {{ formatDigitalGain(exposure.digital_gain) }}
      </p>
    </section>

    <section v-if="whiteBalance">
      <h2>White balance</h2>

      <button
        :disabled="whiteBalanceBusy || whiteBalance.auto"
        @click="setWhiteBalanceAuto"
      >
        Auto
      </button>

      <button
        :disabled="whiteBalanceBusy"
        @click="setWhiteBalanceSingle"
      >
        {{ whiteBalanceBusy ? 'Witbalans meten...' : 'Set white balance' }}
      </button>

      <p>
        Mode: {{ whiteBalance.auto ? 'Auto' : 'Single shot' }}<br>
        Red gain: {{ formatColourGain(whiteBalance.red_gain) }}<br>
        Blue gain: {{ formatColourGain(whiteBalance.blue_gain) }}<br>
        Colour temperature:
        {{ whiteBalance.colour_temperature == null ? '—' : `${whiteBalance.colour_temperature} K` }}
      </p>

      <p v-if="whiteBalanceError">
        Fout bij witbalans: {{ whiteBalanceError }}
      </p>
    </section>

    <section>
      <h2>Foto</h2>

      <label>
        Naam:
        <input
          v-model="photoName"
          :disabled="photoBusy"
          type="text"
        >
      </label>

      <div>
        <button
          :disabled="photoBusy || !photoName.trim()"
          @click="takePhoto"
        >
          {{ photoBusy ? 'Foto maken...' : 'Foto nemen' }}
        </button>
      </div>

      <p v-if="photoError">
        Fout bij foto: {{ photoError }}
      </p>
    </section>

    <img
      :src="'/api/stream'"
      alt="Live camerabeeld"
    >
  </main>
</template>
