<script setup>
import { onMounted, onUnmounted, ref } from 'vue'

const props = defineProps({
  sourceElement: {
    type: Object,
    default: null,
  },
  intervalMs: {
    type: Number,
    default: 500,
  },
})

const histogramCanvas = ref(null)

const SAMPLE_WIDTH = 160
const SAMPLE_HEIGHT = 120
const HISTOGRAM_WIDTH = 256
const HISTOGRAM_HEIGHT = 96

let sampleCanvas = null
let sampleContext = null
let histogramTimer = null
let histogramAbortController = null
let stopped = false

function drawChannel(context, bins, maximum, fillStyle, strokeStyle) {
  context.beginPath()
  context.moveTo(0, HISTOGRAM_HEIGHT)

  for (let value = 0; value < 256; value += 1) {
    const x = value
    const height = (bins[value] / maximum) * (HISTOGRAM_HEIGHT - 2)
    context.lineTo(x, HISTOGRAM_HEIGHT - height)
  }

  context.lineTo(HISTOGRAM_WIDTH - 1, HISTOGRAM_HEIGHT)
  context.closePath()
  context.fillStyle = fillStyle
  context.fill()

  context.beginPath()

  for (let value = 0; value < 256; value += 1) {
    const x = value
    const height = (bins[value] / maximum) * (HISTOGRAM_HEIGHT - 2)
    const y = HISTOGRAM_HEIGHT - height

    if (value === 0) {
      context.moveTo(x, y)
    } else {
      context.lineTo(x, y)
    }
  }

  context.strokeStyle = strokeStyle
  context.lineWidth = 1
  context.stroke()
}

function findJpegRange(bytes) {
  let start = -1

  for (let index = 0; index < bytes.length - 1; index += 1) {
    if (start < 0 && bytes[index] === 0xff && bytes[index + 1] === 0xd8) {
      start = index
      index += 1
      continue
    }

    if (
      start >= 0
      && bytes[index] === 0xff
      && bytes[index + 1] === 0xd9
    ) {
      return [start, index + 2]
    }
  }

  return null
}

function appendBytes(current, next) {
  const combined = new Uint8Array(current.length + next.length)
  combined.set(current)
  combined.set(next, current.length)
  return combined
}

async function fetchCurrentJpeg() {
  histogramAbortController = new AbortController()

  const response = await fetch(`/api/stream?histogram=${Date.now()}`, {
    cache: 'no-store',
    signal: histogramAbortController.signal,
  })

  if (!response.ok || !response.body) {
    throw new Error(`HTTP ${response.status}`)
  }

  const reader = response.body.getReader()
  let bytes = new Uint8Array(0)

  try {
    while (!stopped) {
      const { done, value } = await reader.read()

      if (done) {
        break
      }

      bytes = appendBytes(bytes, value)
      const range = findJpegRange(bytes)

      if (range) {
        const [start, end] = range
        return bytes.slice(start, end)
      }

      // Een previewframe hoort ruim onder deze grens te blijven.
      if (bytes.length > 2 * 1024 * 1024) {
        throw new Error('Previewframe te groot')
      }
    }
  } finally {
    try {
      await reader.cancel()
    } catch (_) {
      // De server kan de stream al gesloten hebben.
    }
  }

  return null
}

function drawHistogramFromPixels(pixels) {
  const canvas = histogramCanvas.value

  if (!canvas) {
    return
  }

  const red = new Uint32Array(256)
  const green = new Uint32Array(256)
  const blue = new Uint32Array(256)

  for (let index = 0; index < pixels.length; index += 4) {
    red[pixels[index]] += 1
    green[pixels[index + 1]] += 1
    blue[pixels[index + 2]] += 1
  }

  let maximum = 1

  for (let value = 0; value < 256; value += 1) {
    maximum = Math.max(maximum, red[value], green[value], blue[value])
  }

  const context = canvas.getContext('2d')
  context.clearRect(0, 0, HISTOGRAM_WIDTH, HISTOGRAM_HEIGHT)
  context.fillStyle = '#ffffff'
  context.fillRect(0, 0, HISTOGRAM_WIDTH, HISTOGRAM_HEIGHT)

  drawChannel(context, blue, maximum, 'rgba(0, 90, 255, 0.32)', 'rgba(0, 70, 220, 0.95)')
  drawChannel(context, green, maximum, 'rgba(0, 180, 60, 0.32)', 'rgba(0, 145, 45, 0.95)')
  drawChannel(context, red, maximum, 'rgba(235, 30, 30, 0.32)', 'rgba(205, 20, 20, 0.95)')
}

async function updateHistogram() {
  if (stopped || !sampleContext) {
    return
  }

  try {
    const jpegBytes = await fetchCurrentJpeg()

    if (!jpegBytes || stopped) {
      return
    }

    const blob = new Blob([jpegBytes], { type: 'image/jpeg' })
    const bitmap = await createImageBitmap(blob)

    try {
      sampleContext.clearRect(0, 0, SAMPLE_WIDTH, SAMPLE_HEIGHT)
      sampleContext.drawImage(bitmap, 0, 0, SAMPLE_WIDTH, SAMPLE_HEIGHT)
      const pixels = sampleContext.getImageData(0, 0, SAMPLE_WIDTH, SAMPLE_HEIGHT).data
      drawHistogramFromPixels(pixels)
    } finally {
      bitmap.close()
    }
  } catch (error) {
    if (error?.name !== 'AbortError') {
      // Een tijdelijk onbeschikbaar frame proberen we bij de volgende update opnieuw.
    }
  } finally {
    histogramAbortController = null

    if (!stopped) {
      histogramTimer = setTimeout(updateHistogram, props.intervalMs)
    }
  }
}

onMounted(() => {
  sampleCanvas = document.createElement('canvas')
  sampleCanvas.width = SAMPLE_WIDTH
  sampleCanvas.height = SAMPLE_HEIGHT
  sampleContext = sampleCanvas.getContext('2d', { willReadFrequently: true })
  stopped = false
  updateHistogram()
})

onUnmounted(() => {
  stopped = true

  if (histogramTimer) {
    clearTimeout(histogramTimer)
    histogramTimer = null
  }

  if (histogramAbortController) {
    histogramAbortController.abort()
    histogramAbortController = null
  }

  sampleCanvas = null
  sampleContext = null
})
</script>

<template>
  <canvas
    ref="histogramCanvas"
    class="rgb-histogram"
    :width="HISTOGRAM_WIDTH"
    :height="HISTOGRAM_HEIGHT"
    aria-label="RGB-histogram van het live camerabeeld"
  ></canvas>
</template>

<style scoped>
.rgb-histogram {
  display: block;
  width: 100%;
  height: 96px;
  margin-top: 6px;
  border: 1px solid var(--ui-border);
  background: #fff;
}
</style>
