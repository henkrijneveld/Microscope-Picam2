import './assets/main.css'

import { createApp } from 'vue'
import App from './App.vue'

const FOCUS_STACK_STORAGE_KEY = 'microrasp-focus-stack'
const nativeFetch = window.fetch.bind(window)

const focusStackState = {
  active: false,
  number: 1,
  timestamp: null,
}

let focusStackBusy = false

function formatStackTimestamp(date) {
  const two = (value) => String(value).padStart(2, '0')

  return [
    two(date.getFullYear() % 100),
    two(date.getMonth() + 1),
    two(date.getDate()),
  ].join('') + '-' + [
    two(date.getHours()),
    two(date.getMinutes()),
    two(date.getSeconds()),
  ].join('')
}

function loadFocusStackState() {
  try {
    const stored = JSON.parse(sessionStorage.getItem(FOCUS_STACK_STORAGE_KEY) || 'null')

    if (
      stored?.active === true
      && Number.isInteger(stored.number)
      && stored.number >= 1
      && /^\d{6}-\d{6}$/.test(stored.timestamp || '')
    ) {
      focusStackState.active = true
      focusStackState.number = stored.number
      focusStackState.timestamp = stored.timestamp
    }
  } catch (_) {
    sessionStorage.removeItem(FOCUS_STACK_STORAGE_KEY)
  }
}

function saveFocusStackState() {
  sessionStorage.setItem(
    FOCUS_STACK_STORAGE_KEY,
    JSON.stringify(focusStackState),
  )
}

function setFocusStacking(active) {
  if (focusStackBusy || focusStackState.active === active) {
    return
  }

  focusStackState.active = active

  if (active) {
    focusStackState.number = 1
    focusStackState.timestamp = formatStackTimestamp(new Date())
  } else {
    focusStackState.number = 1
    focusStackState.timestamp = null
  }

  saveFocusStackState()
  renderFocusStackControls()
}

function renderFocusStackControls() {
  const fovSetting = document.querySelector('#capture-panel .fov-setting')

  if (!fovSetting) {
    return
  }

  let controls = fovSetting.querySelector('[data-focus-stack-controls]')

  if (!controls) {
    controls = document.createElement('span')
    controls.dataset.focusStackControls = ''
    controls.style.display = 'contents'

    const label = document.createElement('span')
    label.textContent = 'Focus stacking'
    label.style.marginLeft = '8px'

    const offButton = document.createElement('button')
    offButton.type = 'button'
    offButton.textContent = 'Uit'
    offButton.dataset.focusStackOff = ''
    offButton.addEventListener('click', () => setFocusStacking(false))

    const activeButton = document.createElement('button')
    activeButton.type = 'button'
    activeButton.textContent = 'Actief'
    activeButton.dataset.focusStackActive = ''
    activeButton.addEventListener('click', () => setFocusStacking(true))

    const number = document.createElement('input')
    number.type = 'text'
    number.readOnly = true
    number.dataset.focusStackNumber = ''
    number.setAttribute('aria-label', 'Stacknummer')
    number.style.width = '46px'
    number.style.textAlign = 'center'

    controls.append(label, offButton, activeButton, number)
    fovSetting.appendChild(controls)
  }

  const offButton = controls.querySelector('[data-focus-stack-off]')
  const activeButton = controls.querySelector('[data-focus-stack-active]')
  const number = controls.querySelector('[data-focus-stack-number]')

  offButton.disabled = focusStackBusy || !focusStackState.active
  activeButton.disabled = focusStackBusy || focusStackState.active
  number.hidden = !focusStackState.active
  number.value = focusStackState.active ? String(focusStackState.number) : ''
  number.title = focusStackState.active
    ? `${focusStackState.timestamp}-${focusStackState.number}-…`
    : ''
}

function isPhotoRequest(input, init) {
  const url = typeof input === 'string' ? input : input?.url
  const method = String(init?.method || input?.method || 'GET').toUpperCase()

  if (!url || method !== 'POST') {
    return false
  }

  try {
    return new URL(url, window.location.href).pathname === '/api/photo'
  } catch (_) {
    return false
  }
}

window.fetch = async function microraspFetch(input, init = undefined) {
  if (!isPhotoRequest(input, init)) {
    return nativeFetch(input, init)
  }

  const stackWasActive = focusStackState.active
  const stackNumber = focusStackState.number
  const stackTimestamp = focusStackState.timestamp
  let nextInit = init

  if (stackWasActive) {
    const headers = new Headers(
      init?.headers || (typeof input !== 'string' ? input.headers : undefined),
    )
    headers.set('X-Microrasp-Stack-Timestamp', stackTimestamp)
    headers.set('X-Microrasp-Stack-Number', String(stackNumber))
    nextInit = {
      ...(init || {}),
      headers,
    }
  }

  focusStackBusy = true
  renderFocusStackControls()

  try {
    const response = await nativeFetch(input, nextInit)

    if (response.ok && stackWasActive) {
      focusStackState.number = stackNumber + 1
      saveFocusStackState()
    }

    return response
  } finally {
    focusStackBusy = false
    renderFocusStackControls()
  }
}

loadFocusStackState()
createApp(App).mount('#app')

function addLatestPhotoNavigation() {
  const navigations = document.querySelectorAll('#navigation-panel, #files-layout nav')

  for (const navigation of navigations) {
    if (navigation.querySelector('[data-latest-photo-nav]')) {
      continue
    }

    const button = document.createElement('button')
    button.type = 'button'
    button.textContent = 'Laatste foto'
    button.dataset.latestPhotoNav = ''
    button.addEventListener('click', () => {
      window.location.href = '/latest.html'
    })

    const buttons = navigation.querySelectorAll('button')
    const stopButton = buttons[buttons.length - 1]
    navigation.insertBefore(button, stopButton || null)
  }
}

function updateInjectedUi() {
  addLatestPhotoNavigation()
  renderFocusStackControls()
}

updateInjectedUi()

const navigationObserver = new MutationObserver(updateInjectedUi)
navigationObserver.observe(document.getElementById('app'), {
  childList: true,
  subtree: true,
})
