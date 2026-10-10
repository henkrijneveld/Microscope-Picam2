import { getLanguage, setLanguage, t } from './latest-photo-translations.js'

const thumbnailPanel = document.getElementById('thumbnail-panel')
const photoPanel = document.getElementById('photo-panel')
const mainPhoto = document.getElementById('main-photo')
const emptyMessage = document.getElementById('empty-message')
const systemStatus = document.getElementById('system-status')
const navigationPanel = document.getElementById('navigation-panel')
const cameraButton = document.getElementById('camera-button')
const filesButton = document.getElementById('files-button')
const latestButton = document.getElementById('latest-button')
const shutdownButton = document.getElementById('shutdown-button')
const languageSwitch = document.getElementById('language-switch')
const languageNl = document.getElementById('language-nl')
const languageEn = document.getElementById('language-en')

const objectUrls = new Map()
let selectedFilename = null
let statusResult = null
let statusError = null
let shuttingDown = false
let photoState = 'loading'
let photoErrorMessage = ''

function fileUrl(filename) {
  return `/api/files/${encodeURIComponent(filename)}`
}

function setSystemStatus(primary, detail = '') {
  systemStatus.innerHTML = ''

  const primaryElement = document.createElement('span')
  primaryElement.className = 'status-primary'
  primaryElement.textContent = primary
  systemStatus.appendChild(primaryElement)

  if (detail) {
    const detailElement = document.createElement('span')
    detailElement.className = 'status-detail'
    detailElement.textContent = detail
    systemStatus.appendChild(detailElement)
  }
}

function renderSystemStatus() {
  if (shuttingDown) {
    setSystemStatus(t('status.shuttingDown'), t('status.shutdownWait'))
    return
  }

  if (statusError) {
    setSystemStatus(`MicroRasp: ${t('common.error')}`, statusError)
    return
  }

  if (!statusResult) {
    setSystemStatus('MicroRasp', t('common.loadingStatus'))
    return
  }

  if (!statusResult.camera?.connected) {
    setSystemStatus(
      `MicroRasp: ${t('common.error')}`,
      [t('status.cameraNotConnected'), statusResult.camera?.error].filter(Boolean).join(' · '),
    )
    return
  }

  const detail = [
    statusResult.camera.model || t('common.unknownModel'),
    statusResult.camera.hostname || '—',
    statusResult.camera.ip_address || '—',
  ].join(' · ')

  setSystemStatus(`MicroRasp: ${statusResult.status}`, detail)
}

function renderPhotoMessage() {
  emptyMessage.className = ''

  if (photoState === 'loading') {
    emptyMessage.textContent = t('photo.loading')
  } else if (photoState === 'none') {
    emptyMessage.textContent = t('photo.none')
  } else if (photoState === 'error') {
    emptyMessage.className = 'error-message'
    emptyMessage.textContent = t('photo.error', { message: photoErrorMessage })
  }
}

function applyLanguage() {
  const currentLanguage = getLanguage()

  document.documentElement.lang = currentLanguage
  document.title = t('page.title')

  navigationPanel.setAttribute('aria-label', t('aria.mainNavigation'))
  languageSwitch.setAttribute('aria-label', t('aria.language'))
  thumbnailPanel.setAttribute('aria-label', t('aria.latestHdr'))
  photoPanel.setAttribute('aria-label', t('aria.latestPhoto'))

  cameraButton.textContent = t('navigation.camera')
  filesButton.textContent = t('navigation.files')
  latestButton.textContent = t('navigation.latestPhoto')
  shutdownButton.textContent = t('navigation.stopPi')

  languageNl.disabled = currentLanguage === 'nl'
  languageEn.disabled = currentLanguage === 'en'

  if (!selectedFilename) {
    mainPhoto.alt = t('aria.latestPhoto')
  }

  renderSystemStatus()
  renderPhotoMessage()
}

async function loadStatus() {
  statusError = null

  try {
    const response = await fetch('/api/status')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    statusResult = await response.json()
  } catch (error) {
    statusResult = null
    statusError = error.message
  }

  renderSystemStatus()
}

function aebValue(filename) {
  const marker = filename.lastIndexOf('-AEB-')

  if (marker < 0) {
    return 0
  }

  let label = filename.slice(marker + 5).replace(/\.jpg$/i, '')
  label = label.replace(/-\d+$/, '')

  if (label === '0') {
    return 0
  }

  if (label.startsWith('min')) {
    return -Number(label.slice(3))
  }

  if (label.startsWith('plus')) {
    return Number(label.slice(4))
  }

  return 0
}

function latestCapture(files) {
  if (!files.length) {
    return []
  }

  const sorted = [...files].sort((left, right) => (
    new Date(right.modified).getTime() - new Date(left.modified).getTime()
  ))

  const latest = sorted[0]
  const marker = latest.name.lastIndexOf('-AEB-')

  if (marker < 0) {
    return [latest]
  }

  const prefix = latest.name.slice(0, marker)
  const group = sorted
    .filter((file) => file.name.startsWith(`${prefix}-AEB-`))
    .slice(0, 5)

  group.sort((left, right) => aebValue(left.name) - aebValue(right.name))
  return group
}

async function getObjectUrl(filename) {
  if (objectUrls.has(filename)) {
    return objectUrls.get(filename)
  }

  const response = await fetch(fileUrl(filename))

  if (!response.ok) {
    throw new Error(`HTTP ${response.status}`)
  }

  const blob = await response.blob()
  const url = URL.createObjectURL(blob)
  objectUrls.set(filename, url)
  return url
}

async function showPhoto(filename) {
  selectedFilename = filename
  mainPhoto.src = await getObjectUrl(filename)
  mainPhoto.alt = filename
  mainPhoto.hidden = false
  emptyMessage.hidden = true

  for (const button of thumbnailPanel.querySelectorAll('.thumbnail-button')) {
    button.classList.toggle('selected', button.dataset.filename === filename)
  }
}

async function renderLatestPhoto() {
  photoState = 'loading'
  photoErrorMessage = ''
  renderPhotoMessage()

  try {
    const response = await fetch('/api/files')

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    const result = await response.json()
    const capture = latestCapture(result.files || [])

    if (!capture.length) {
      selectedFilename = null
      photoState = 'none'
      thumbnailPanel.hidden = true
      mainPhoto.hidden = true
      emptyMessage.hidden = false
      renderPhotoMessage()
      return
    }

    const isHdr = capture.length > 1
    thumbnailPanel.hidden = !isHdr
    thumbnailPanel.innerHTML = ''

    if (isHdr) {
      for (const file of capture) {
        const button = document.createElement('button')
        button.type = 'button'
        button.className = 'thumbnail-button'
        button.dataset.filename = file.name
        button.title = file.name

        const image = document.createElement('img')
        image.src = await getObjectUrl(file.name)
        image.alt = file.name
        button.appendChild(image)

        button.addEventListener('click', () => {
          showPhoto(file.name)
        })

        thumbnailPanel.appendChild(button)
      }
    }

    const middle = capture[Math.floor(capture.length / 2)]
    photoState = 'ready'
    await showPhoto(middle.name)
  } catch (error) {
    selectedFilename = null
    photoState = 'error'
    photoErrorMessage = error.message
    thumbnailPanel.hidden = true
    mainPhoto.hidden = true
    emptyMessage.hidden = false
    renderPhotoMessage()
  }
}

async function shutdownPi() {
  if (!window.confirm(t('confirm.shutdown'))) {
    return
  }

  try {
    const response = await fetch('/api/system/shutdown', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({ confirm: 'shutdown' }),
    })

    if (!response.ok) {
      throw new Error(`HTTP ${response.status}`)
    }

    shuttingDown = true
    renderSystemStatus()
  } catch (error) {
    statusError = error.message
    setSystemStatus(t('status.shutdownError'), error.message)
  }
}

cameraButton.addEventListener('click', () => {
  window.location.href = '/'
})

filesButton.addEventListener('click', () => {
  window.location.href = '/#files'
})

shutdownButton.addEventListener('click', shutdownPi)

languageNl.addEventListener('click', () => {
  setLanguage('nl')
  applyLanguage()
})

languageEn.addEventListener('click', () => {
  setLanguage('en')
  applyLanguage()
})

window.addEventListener('beforeunload', () => {
  for (const url of objectUrls.values()) {
    URL.revokeObjectURL(url)
  }
})

applyLanguage()
loadStatus()
renderLatestPhoto()
