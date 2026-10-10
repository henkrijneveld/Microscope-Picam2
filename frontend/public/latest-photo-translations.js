const LANGUAGE_STORAGE_KEY = 'microrasp-language'
const SUPPORTED_LANGUAGES = new Set(['nl', 'en'])

const translations = {
  nl: {
    'page.title': 'MicroRasp - Laatste foto',
    'aria.mainNavigation': 'Hoofdnavigatie',
    'aria.language': 'Taal',
    'aria.latestHdr': 'Laatste HDR-opnamen',
    'aria.latestPhoto': 'Laatste foto',

    'navigation.camera': 'Camera',
    'navigation.files': 'Bestanden',
    'navigation.latestPhoto': 'Laatste foto',
    'navigation.stopPi': 'Stop Pi',

    'common.connected': 'verbonden',
    'common.unknownModel': 'model onbekend',
    'common.loadingStatus': 'status ophalen...',
    'common.error': 'fout',

    'status.cameraNotConnected': 'camera niet verbonden',
    'status.shuttingDown': 'Pi wordt afgesloten',
    'status.shutdownWait': 'Wacht tot de Pi volledig uit is voordat de voeding wordt losgenomen.',
    'status.shutdownError': 'Afsluitfout',

    'photo.loading': 'Laatste foto ophalen...',
    'photo.none': 'Nog geen foto opgeslagen.',
    'photo.error': 'Fout bij laatste foto: {message}',

    'confirm.shutdown': 'Pi volledig uitschakelen?',
  },

  en: {
    'page.title': 'MicroRasp - Latest photo',
    'aria.mainNavigation': 'Main navigation',
    'aria.language': 'Language',
    'aria.latestHdr': 'Latest HDR captures',
    'aria.latestPhoto': 'Latest photo',

    'navigation.camera': 'Camera',
    'navigation.files': 'Files',
    'navigation.latestPhoto': 'Latest photo',
    'navigation.stopPi': 'Shut down Pi',

    'common.connected': 'connected',
    'common.unknownModel': 'model unknown',
    'common.loadingStatus': 'loading status...',
    'common.error': 'error',

    'status.cameraNotConnected': 'camera not connected',
    'status.shuttingDown': 'Pi is shutting down',
    'status.shutdownWait': 'Wait until the Pi is fully shut down before disconnecting the power.',
    'status.shutdownError': 'Shutdown error',

    'photo.loading': 'Loading latest photo...',
    'photo.none': 'No photo saved yet.',
    'photo.error': 'Error loading latest photo: {message}',

    'confirm.shutdown': 'Shut down the Pi completely?',
  },
}

function browserLanguage() {
  const browserLanguages = navigator.languages?.length
    ? navigator.languages
    : [navigator.language]

  for (const candidate of browserLanguages) {
    const code = candidate?.split('-')[0]?.toLowerCase()
    if (SUPPORTED_LANGUAGES.has(code)) {
      return code
    }
  }

  return 'nl'
}

let language = browserLanguage()

try {
  const stored = localStorage.getItem(LANGUAGE_STORAGE_KEY)
  if (SUPPORTED_LANGUAGES.has(stored)) {
    language = stored
  }
} catch (_) {
  // Use browser language if storage is blocked.
}

export function getLanguage() {
  return language
}

export function setLanguage(nextLanguage) {
  if (!SUPPORTED_LANGUAGES.has(nextLanguage)) {
    return
  }

  language = nextLanguage

  try {
    localStorage.setItem(LANGUAGE_STORAGE_KEY, nextLanguage)
  } catch (_) {
    // The current page still works when local storage is unavailable.
  }

  document.documentElement.lang = nextLanguage
}

export function t(key, values = {}) {
  const template = translations[language]?.[key]
    ?? translations.nl[key]
    ?? key

  return template.replace(/\{(\w+)\}/g, (match, name) => {
    return Object.prototype.hasOwnProperty.call(values, name)
      ? String(values[name])
      : match
  })
}

document.documentElement.lang = language
