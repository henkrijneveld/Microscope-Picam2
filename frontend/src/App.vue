<script setup>
import { onMounted, onUnmounted, ref } from 'vue'

const status = ref(null)
const error = ref(null)

const exposure = ref(null)

let exposureTimer = null

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
        Exposure: {{ exposure.exposure_time_us }} µs
      </p>
    </section>

    <img
      :src="'/api/stream'"
      alt="Live camerabeeld"
    >
  </main>
</template>
