<script setup>
import { ref, watch } from 'vue'

const props = defineProps({
  modelValue: {
    type: Number,
    required: true,
  },
  step: {
    type: Number,
    default: 1,
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

const draft = ref(String(props.modelValue))
const editing = ref(false)

watch(
  () => props.modelValue,
  (value) => {
    if (!editing.value) {
      draft.value = String(value)
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
    draft.value = String(props.modelValue)
    return
  }

  const nextValue = clamp(number)
  draft.value = String(nextValue)
  emit('commit', nextValue)
}

function stepBy(multiplier) {
  const current = Number(draft.value)
  const base = Number.isFinite(current) ? current : props.modelValue
  commit(base + multiplier * props.step)
}

function commitDraft() {
  editing.value = false
  commit(draft.value)
}

function handleKeydown(event) {
  if (event.key === 'Enter') {
    event.currentTarget.blur()
  }

  if (event.key === 'Escape') {
    draft.value = String(props.modelValue)
    event.currentTarget.blur()
  }
}
</script>

<template>
  <div class="number-stepper">
    <button :disabled="disabled" type="button" @click="stepBy(-10)">
      -10
    </button>
    <button :disabled="disabled" type="button" @click="stepBy(-1)">
      -1
    </button>
    <input
      v-model="draft"
      :disabled="disabled"
      :step="step"
      type="number"
      inputmode="decimal"
      @focus="editing = true"
      @blur="commitDraft"
      @keydown="handleKeydown"
    >
    <span v-if="suffix" class="number-stepper-suffix">{{ suffix }}</span>
    <button :disabled="disabled" type="button" @click="stepBy(1)">
      +1
    </button>
    <button :disabled="disabled" type="button" @click="stepBy(10)">
      +10
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
