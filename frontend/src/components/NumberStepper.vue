<script setup>
import { computed, ref, watch } from 'vue'

const props = defineProps({
  modelValue: {
    type: Number,
    required: true,
  },
  step: {
    type: Number,
    default: 1,
  },
  innerStep: {
    type: Number,
    default: null,
  },
  outerStep: {
    type: Number,
    default: null,
  },
  min: {
    type: Number,
    default: null,
  },
  max: {
    type: Number,
    default: null,
  },
  suffix: {
    type: String,
    default: '',
  },
  disabled: {
    type: Boolean,
    default: false,
  },
})

const emit = defineEmits(['commit'])

const activeInnerStep = computed(() => (
  props.innerStep == null ? props.step : props.innerStep
))
const activeOuterStep = computed(() => (
  props.outerStep == null ? props.step * 10 : props.outerStep
))

function decimalPlaces(value) {
  const number = Math.abs(Number(value))

  if (!Number.isFinite(number) || number === 0) {
    return 0
  }

  const text = String(number).toLowerCase()

  if (text.includes('e-')) {
    return Number(text.split('e-')[1]) || 0
  }

  const decimalPart = text.split('.')[1]
  return decimalPart ? decimalPart.length : 0
}

function stepDecimals() {
  return Math.max(
    decimalPlaces(props.step),
    decimalPlaces(activeInnerStep.value),
    decimalPlaces(activeOuterStep.value),
  )
}

function formatValue(value) {
  const number = Number(value)

  if (!Number.isFinite(number)) {
    return String(value)
  }

  return number.toFixed(stepDecimals())
}

function formatButtonStep(value) {
  const number = Number(value)

  if (!Number.isFinite(number)) {
    return String(value)
  }

  return String(Number(number.toFixed(stepDecimals()))).replace('.', ',')
}

function buttonLabel(direction, amount) {
  return `${direction < 0 ? '-' : '+'}${formatButtonStep(amount)}`
}

const draft = ref(formatValue(props.modelValue))
const editing = ref(false)
const suppressBlurCommit = ref(false)

watch(
  () => [props.modelValue, props.step, props.innerStep, props.outerStep],
  ([value]) => {
    if (!editing.value) {
      draft.value = formatValue(value)
    }
  },
)

function clamp(value) {
  let result = value

  if (props.min != null) {
    result = Math.max(props.min, result)
  }

  if (props.max != null) {
    result = Math.min(props.max, result)
  }

  return result
}

function commit(value) {
  const number = Number(value)

  if (!Number.isFinite(number)) {
    draft.value = formatValue(props.modelValue)
    return
  }

  const nextValue = clamp(number)
  draft.value = formatValue(nextValue)
  emit('commit', nextValue)
}

function prepareButtonAction() {
  suppressBlurCommit.value = true
}

function stepBy(delta) {
  suppressBlurCommit.value = false
  const current = Number(draft.value)
  const base = Number.isFinite(current) ? current : props.modelValue
  commit(base + delta)
}

function commitDraft() {
  editing.value = false

  if (suppressBlurCommit.value) {
    suppressBlurCommit.value = false
    return
  }

  commit(draft.value)
}

function handleKeydown(event) {
  if (event.key === 'Enter') {
    event.currentTarget.blur()
  }

  if (event.key === 'Escape') {
    draft.value = formatValue(props.modelValue)
    event.currentTarget.blur()
  }
}
</script>

<template>
  <div class="number-stepper">
    <button
      :disabled="disabled"
      type="button"
      @mousedown="prepareButtonAction"
      @click="stepBy(-activeOuterStep)"
    >
      {{ buttonLabel(-1, activeOuterStep) }}
    </button>
    <button
      :disabled="disabled"
      type="button"
      @mousedown="prepareButtonAction"
      @click="stepBy(-activeInnerStep)"
    >
      {{ buttonLabel(-1, activeInnerStep) }}
    </button>
    <input
      v-model="draft"
      :disabled="disabled"
      :step="step"
      :min="min"
      :max="max"
      type="number"
      inputmode="decimal"
      @focus="editing = true"
      @blur="commitDraft"
      @keydown="handleKeydown"
    >
    <span v-if="suffix" class="number-stepper-suffix">{{ suffix }}</span>
    <button
      :disabled="disabled"
      type="button"
      @mousedown="prepareButtonAction"
      @click="stepBy(activeInnerStep)"
    >
      {{ buttonLabel(1, activeInnerStep) }}
    </button>
    <button
      :disabled="disabled"
      type="button"
      @mousedown="prepareButtonAction"
      @click="stepBy(activeOuterStep)"
    >
      {{ buttonLabel(1, activeOuterStep) }}
    </button>
  </div>
</template>

<style scoped>
.number-stepper {
  display: grid;
  grid-template-columns: auto auto minmax(58px, 1fr) auto auto auto;
  align-items: center;
  gap: 4px;
  min-width: 0;
  margin-block: 4px;
}

.number-stepper button {
  min-width: 0;
  padding-inline: 5px;
}

.number-stepper input {
  min-width: 0;
  width: 100%;
  min-height: 28px;
  padding: 2px 4px;
  text-align: center;
}

.number-stepper-suffix {
  white-space: nowrap;
  font-size: 0.86rem;
}
</style>
