import { fileURLToPath, URL } from 'node:url'


import { defineConfig, loadEnv } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

const PROJECT_DIR = fileURLToPath(new URL('..', import.meta.url))

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, PROJECT_DIR, '')

  return {
    envDir: PROJECT_DIR,
    plugins: [
      vue(),
      vueDevTools(),
    ],

    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url)),
      },
    },

    server: {
      proxy: {
        '/api': {
          target: env.PICAM_API_TARGET,
          changeOrigin: true,
        },
      },
    },
  }
})
