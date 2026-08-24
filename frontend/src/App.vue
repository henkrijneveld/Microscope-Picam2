<script setup>
import { onMounted, ref } from 'vue'

const status = ref(null)
const error = ref(null)

onMounted(async () => {
  try {
    const response = await fetch('/api/status')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    status.value = await response.json()
  } catch (exc) {
    error.value = exc.message
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

    <img
      :src="'/api/stream'"
      alt="Live camerabeeld"
    >
  </main>
</template>
