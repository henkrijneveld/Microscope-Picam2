import './assets/main.css'

import { createApp } from 'vue'
import App from './App.vue'

const FOCUS_STACK_STORAGE_KEY = 'microrasp-focus-stack'
const FILES_PER_PAGE = 16
const nativeFetch = window.fetch.bind(window)

const focusStackState = {
  active: false,
  number: 1,
  timestamp: null,
}

let focusStackBusy = false
let filesPage = 0

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

function setFilesSystemStatus(element, primary, detail = '') {
  element.innerHTML = ''

  const primaryElement = document.createElement('span')
  primaryElement.className = 'status-primary'
  primaryElement.textContent = primary
  element.appendChild(primaryElement)

  if (detail) {
    const detailElement = document.createElement('span')
    detailElement.className = 'status-detail'
    detailElement.textContent = detail
    element.appendChild(detailElement)
  }
}

async function loadFilesSystemStatus(element) {
  try {
    const response = await nativeFetch('/api/status')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    const result = await response.json()

    if (!result.camera?.connected) {
      setFilesSystemStatus(element, 'MicroRasp: fout', 'camera niet verbonden')
      return
    }

    const detail = [
      'verbonden',
      result.camera.model || 'model onbekend',
      result.camera.hostname || '—',
      result.camera.ip_address || '—',
    ].join(' · ')

    setFilesSystemStatus(element, `MicroRasp: ${result.status}`, detail)
  } catch (error) {
    setFilesSystemStatus(element, 'MicroRasp: fout', error.message)
  }
}

function updateFilesPagination() {
  const panel = document.getElementById('files-panel')

  if (!panel) {
    return
  }

  const rows = Array.from(panel.querySelectorAll('tbody tr'))
  const totalPages = rows.length ? Math.ceil(rows.length / FILES_PER_PAGE) : 0

  if (totalPages === 0) {
    filesPage = 0
  } else {
    filesPage = Math.max(0, Math.min(filesPage, totalPages - 1))
  }

  const start = filesPage * FILES_PER_PAGE
  const end = start + FILES_PER_PAGE

  rows.forEach((row, index) => {
    row.hidden = index < start || index >= end
  })

  const previous = panel.querySelector('[data-files-previous]')
  const next = panel.querySelector('[data-files-next]')
  const indicator = panel.querySelector('[data-files-page]')

  if (previous) {
    previous.disabled = totalPages <= 1 || filesPage === 0
  }

  if (next) {
    next.disabled = totalPages <= 1 || filesPage >= totalPages - 1
  }

  if (indicator) {
    indicator.textContent = totalPages ? `${filesPage + 1} / ${totalPages}` : '0 / 0'
  }
}

function enhanceFilesPage() {
  const layout = document.getElementById('files-layout')

  if (!layout) {
    return
  }

  let header = document.getElementById('files-topbar')

  if (!header) {
    filesPage = 0

    const navigation = layout.querySelector('nav')
    const panel = layout.querySelector('section.ui-panel')

    if (!navigation || !panel) {
      return
    }

    header = document.createElement('header')
    header.id = 'files-topbar'
    layout.insertBefore(header, navigation)

    navigation.id = 'files-navigation-panel'
    header.appendChild(navigation)

    const systemStatus = document.createElement('section')
    systemStatus.id = 'files-system-status'
    systemStatus.setAttribute('aria-live', 'polite')
    setFilesSystemStatus(systemStatus, 'MicroRasp', 'status ophalen...')
    header.appendChild(systemStatus)
    loadFilesSystemStatus(systemStatus)

    panel.id = 'files-panel'

    const pager = document.createElement('div')
    pager.className = 'files-pager'

    const previous = document.createElement('button')
    previous.type = 'button'
    previous.textContent = 'Vorige'
    previous.dataset.filesPrevious = ''
    previous.addEventListener('click', () => {
      if (filesPage > 0) {
        filesPage -= 1
        updateFilesPagination()
      }
    })

    const indicator = document.createElement('span')
    indicator.dataset.filesPage = ''
    indicator.className = 'files-page-indicator'

    const next = document.createElement('button')
    next.type = 'button'
    next.textContent = 'Volgende'
    next.dataset.filesNext = ''
    next.addEventListener('click', () => {
      const rowCount = panel.querySelectorAll('tbody tr').length
      const totalPages = Math.ceil(rowCount / FILES_PER_PAGE)

      if (filesPage < totalPages - 1) {
        filesPage += 1
        updateFilesPagination()
      }
    })

    pager.append(previous, indicator, next)
    panel.appendChild(pager)
  }

  updateFilesPagination()
}

function updateInjectedUi() {
  addLatestPhotoNavigation()
  renderFocusStackControls()
  enhanceFilesPage()
}

updateInjectedUi()

const navigationObserver = new MutationObserver(updateInjectedUi)
navigationObserver.observe(document.getElementById('app'), {
  childList: true,
  subtree: true,
})
