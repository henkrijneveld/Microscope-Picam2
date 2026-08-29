<script setup>
import { onMounted, onUnmounted, ref } from 'vue'

const status = ref(null)
const error = ref(null)

const exposure = ref(null)
const framerate = ref(null)

let exposureTimer = null

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

    exposureTimer = setInterval(loadExposure, 500)
  } catch (exc) {
    error.value = exc.message
  }
})

onUnmounted(() => {
  if (exposureTimer) {
    clearInterval(exposureTimer)
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

    <img
      :src="'/api/stream'"
      alt="Live camerabeeld"
    >
  </main>
</template>
