import './assets/main.css'

import { createApp } from 'vue'
import App from './App.vue'

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

addLatestPhotoNavigation()

const navigationObserver = new MutationObserver(addLatestPhotoNavigation)
navigationObserver.observe(document.getElementById('app'), {
  childList: true,
  subtree: true,
})
