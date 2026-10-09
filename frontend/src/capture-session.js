const CAPTURE_SETTINGS_STORAGE_KEY = 'microrasp-capture-settings'

const DEFAULT_CAPTURE_SETTINGS = {
  photoName: 'microscope',
  captureMode: 'single',
  fovValue: '',
  fovUnit: 'mm',
}

const CAPTURE_MODES = new Set(['single', 'hdr3', 'hdr5'])
const FOV_UNITS = new Set(['µm', 'mm', 'cm'])

function loadCaptureSettings() {
  try {
    const stored = JSON.parse(sessionStorage.getItem(CAPTURE_SETTINGS_STORAGE_KEY) || 'null')

    if (!stored || typeof stored !== 'object') {
      return { ...DEFAULT_CAPTURE_SETTINGS }
    }

    return {
      photoName: typeof stored.photoName === 'string'
        ? stored.photoName
        : DEFAULT_CAPTURE_SETTINGS.photoName,
      captureMode: CAPTURE_MODES.has(stored.captureMode)
        ? stored.captureMode
        : DEFAULT_CAPTURE_SETTINGS.captureMode,
      fovValue: typeof stored.fovValue === 'string'
        ? stored.fovValue
        : DEFAULT_CAPTURE_SETTINGS.fovValue,
      fovUnit: FOV_UNITS.has(stored.fovUnit)
        ? stored.fovUnit
        : DEFAULT_CAPTURE_SETTINGS.fovUnit,
    }
  } catch (_) {
    sessionStorage.removeItem(CAPTURE_SETTINGS_STORAGE_KEY)
    return { ...DEFAULT_CAPTURE_SETTINGS }
  }
}

let captureSettings = loadCaptureSettings()
let restoredPanel = null

function saveCaptureSettings() {
  sessionStorage.setItem(
    CAPTURE_SETTINGS_STORAGE_KEY,
    JSON.stringify(captureSettings),
  )
}

function setInputValue(input, value) {
  if (!input || input.value === value) {
    return
  }

  input.value = value
  input.dispatchEvent(new Event('input', { bubbles: true }))
}

function buttonText(button) {
  return button?.textContent?.trim() || ''
}

function captureModeFromButton(button) {
  const label = buttonText(button)

  if (label === 'HDR-3') {
    return 'hdr3'
  }

  if (label === 'HDR-5') {
    return 'hdr5'
  }

  return label === 'Enkel' ? 'single' : null
}

function captureModeLabel(mode) {
  if (mode === 'hdr3') {
    return 'HDR-3'
  }

  if (mode === 'hdr5') {
    return 'HDR-5'
  }

  return 'Enkel'
}

function restoreCaptureSettings() {
  const panel = document.getElementById('capture-panel')

  if (!panel || panel === restoredPanel) {
    return
  }

  const photoName = panel.querySelector('.photo-name input')
  const fovValue = panel.querySelector('.fov-setting input')
  setInputValue(photoName, captureSettings.photoName)
  setInputValue(fovValue, captureSettings.fovValue)

  const modeButton = Array.from(panel.querySelectorAll('.capture-mode button'))
    .find((button) => buttonText(button) === captureModeLabel(captureSettings.captureMode))
  if (modeButton && !modeButton.disabled) {
    modeButton.click()
  }

  const unitButton = Array.from(panel.querySelectorAll('.fov-setting button'))
    .find((button) => buttonText(button) === captureSettings.fovUnit)
  if (unitButton && !unitButton.disabled) {
    unitButton.click()
  }

  restoredPanel = panel
}

document.addEventListener('input', (event) => {
  const target = event.target

  if (target?.matches?.('#capture-panel .photo-name input')) {
    captureSettings.photoName = target.value
    saveCaptureSettings()
  } else if (target?.matches?.('#capture-panel .fov-setting input')) {
    captureSettings.fovValue = target.value
    saveCaptureSettings()
  }
})

document.addEventListener('click', (event) => {
  const button = event.target?.closest?.('#capture-panel button')

  if (!button) {
    return
  }

  if (button.closest('.capture-mode')) {
    const mode = captureModeFromButton(button)

    if (mode) {
      captureSettings.captureMode = mode
      saveCaptureSettings()
    }
    return
  }

  if (button.closest('.fov-setting')) {
    const unit = buttonText(button)

    if (FOV_UNITS.has(unit)) {
      captureSettings.fovUnit = unit
      saveCaptureSettings()
    }
  }
})

const observer = new MutationObserver(restoreCaptureSettings)
observer.observe(document.documentElement, {
  childList: true,
  subtree: true,
})

restoreCaptureSettings()
