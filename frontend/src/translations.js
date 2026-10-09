import { ref } from 'vue'

const LANGUAGE_STORAGE_KEY = 'microrasp-language'
const SUPPORTED_LANGUAGES = new Set(['nl', 'en'])

function storedLanguage() {
  try {
    const value = localStorage.getItem(LANGUAGE_STORAGE_KEY)
    return SUPPORTED_LANGUAGES.has(value) ? value : 'nl'
  } catch (_) {
    return 'nl'
  }
}

export const language = ref(storedLanguage())

export const translations = {
  nl: {
    'aria.mainNavigation': 'Hoofdnavigatie',
    'aria.language': 'Taal',
    'aria.livePreview': 'Live voorbeeld',
    'aria.liveCameraImage': 'Live camerabeeld',
    'aria.cameraSettings': 'Camerainstellingen',
    'aria.capturePhoto': 'Foto opnemen',
    'aria.fov': 'Beeldveld (FOV)',
    'aria.stackNumber': 'Stacknummer',
    'aria.rgbHistogram': 'RGB-histogram van het live camerabeeld',

    'navigation.camera': 'Camera',
    'navigation.files': 'Bestanden',
    'navigation.latestPhoto': 'Laatste foto',
    'navigation.stopPi': 'Stop Pi',
    'navigation.stoppingPi': 'Pi stoppen...',

    'common.auto': 'Auto',
    'common.manual': 'Handmatig',
    'common.connected': 'verbonden',
    'common.notConnected': 'niet verbonden',
    'common.unknownModel': 'model onbekend',
    'common.loadingStatus': 'status ophalen...',
    'common.error': 'Fout',
    'common.off': 'Uit',
    'common.active': 'Actief',
    'common.refresh': 'Verversen',
    'common.refreshing': 'Verversen...',
    'common.download': 'Download',

    'status.shuttingDown': 'Pi wordt afgesloten',
    'status.shutdownWait': 'Wacht tot de Pi volledig uit is voordat de voeding wordt losgenomen.',
    'status.shutdownError': 'Afsluitfout',
    'status.cameraError': 'Camerafout',
    'status.cameraNotConnected': 'camera niet verbonden',

    'frameRate.title': 'Framesnelheid',
    'frameRate.current': 'Huidig',

    'exposure.title': 'Belichting',
    'exposure.analogue': 'Analoog',
    'exposure.digital': 'Digitaal',

    'whiteBalance.title': 'Witbalans',
    'whiteBalance.measuring': 'Meten...',
    'whiteBalance.red': 'Rood',
    'whiteBalance.blue': 'Blauw',
    'whiteBalance.noRgbSample': 'Geen bruikbare RGB-meting beschikbaar',

    'saturation.title': 'Verzadiging',
    'saturation.range': 'Bereik',
    'saturation.setting': 'instellen...',

    'capture.photoName': 'Foto naam',
    'capture.mode': 'Opname',
    'capture.single': 'Enkel',
    'capture.takePhoto': 'Foto nemen',
    'capture.taking': 'Foto maken...',
    'capture.takingMode': '{mode} maken...',
    'capture.captureMode': '{mode} opname',
    'capture.fovPlaceholder': 'getal',
    'capture.making': 'Foto wordt gemaakt…',
    'capture.saved': 'Opgeslagen:',
    'capture.ready': 'Gereed',
    'capture.fovPositive': 'FOV moet een positief getal zijn',

    'focus.label': 'Focus stacking',

    'files.title': 'Bestanden',
    'files.folder': 'Map op Pi:',
    'files.error': 'Fout bij bestanden:',
    'files.none': "Nog geen foto's opgeslagen.",
    'files.file': 'Bestand',
    'files.size': 'Grootte',

    'pagination.previous': 'Vorige',
    'pagination.next': 'Volgende',

    'confirm.shutdown': 'Pi volledig uitschakelen?',
    'errors.jpegDecode': 'JPEG-frame kon niet worden gedecodeerd',
  },

  en: {
    'aria.mainNavigation': 'Main navigation',
    'aria.language': 'Language',
    'aria.livePreview': 'Live preview',
    'aria.liveCameraImage': 'Live camera image',
    'aria.cameraSettings': 'Camera settings',
    'aria.capturePhoto': 'Take photo',
    'aria.fov': 'Field of view (FOV)',
    'aria.stackNumber': 'Stack number',
    'aria.rgbHistogram': 'RGB histogram of the live camera image',

    'navigation.camera': 'Camera',
    'navigation.files': 'Files',
    'navigation.latestPhoto': 'Latest photo',
    'navigation.stopPi': 'Shut down Pi',
    'navigation.stoppingPi': 'Shutting down Pi...',

    'common.auto': 'Auto',
    'common.manual': 'Manual',
    'common.connected': 'connected',
    'common.notConnected': 'not connected',
    'common.unknownModel': 'model unknown',
    'common.loadingStatus': 'loading status...',
    'common.error': 'Error',
    'common.off': 'Off',
    'common.active': 'Active',
    'common.refresh': 'Refresh',
    'common.refreshing': 'Refreshing...',
    'common.download': 'Download',

    'status.shuttingDown': 'Pi is shutting down',
    'status.shutdownWait': 'Wait until the Pi is fully shut down before disconnecting the power.',
    'status.shutdownError': 'Shutdown error',
    'status.cameraError': 'Camera error',
    'status.cameraNotConnected': 'camera not connected',

    'frameRate.title': 'Frame rate',
    'frameRate.current': 'Current',

    'exposure.title': 'Exposure',
    'exposure.analogue': 'Analogue',
    'exposure.digital': 'Digital',

    'whiteBalance.title': 'White balance',
    'whiteBalance.measuring': 'Measuring...',
    'whiteBalance.red': 'Red',
    'whiteBalance.blue': 'Blue',
    'whiteBalance.noRgbSample': 'No usable RGB measurement available',

    'saturation.title': 'Saturation',
    'saturation.range': 'Range',
    'saturation.setting': 'setting...',

    'capture.photoName': 'Photo name',
    'capture.mode': 'Capture',
    'capture.single': 'Single',
    'capture.takePhoto': 'Take photo',
    'capture.taking': 'Taking photo...',
    'capture.takingMode': 'Taking {mode}...',
    'capture.captureMode': '{mode} capture',
    'capture.fovPlaceholder': 'value',
    'capture.making': 'Photo is being taken…',
    'capture.saved': 'Saved:',
    'capture.ready': 'Ready',
    'capture.fovPositive': 'FOV must be a positive number',

    'focus.label': 'Focus stacking',

    'files.title': 'Files',
    'files.folder': 'Folder on Pi:',
    'files.error': 'File error:',
    'files.none': 'No photos saved yet.',
    'files.file': 'File',
    'files.size': 'Size',

    'pagination.previous': 'Previous',
    'pagination.next': 'Next',

    'confirm.shutdown': 'Shut down the Pi completely?',
    'errors.jpegDecode': 'JPEG frame could not be decoded',
  },
}

export function setLanguage(nextLanguage) {
  if (!SUPPORTED_LANGUAGES.has(nextLanguage)) {
    return
  }

  language.value = nextLanguage

  try {
    localStorage.setItem(LANGUAGE_STORAGE_KEY, nextLanguage)
  } catch (_) {
    // Local storage may be unavailable; the current session still works.
  }

  document.documentElement.lang = nextLanguage
}

export function t(key, values = {}) {
  const template = translations[language.value]?.[key]
    ?? translations.nl[key]
    ?? key

  return template.replace(/\{(\w+)\}/g, (match, name) => {
    return Object.prototype.hasOwnProperty.call(values, name)
      ? String(values[name])
      : match
  })
}

document.documentElement.lang = language.value
