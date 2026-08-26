import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import path from 'node:path'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, 'src'),
    },
  },
  server: {
    port: 5173,
  },
  build: {
    rollupOptions: {
      output: {
        // Give the map chunk a stable, readable name in the build output.
        // Because map.tsx is dynamically imported, Rollup will automatically
        // create a separate file for it — this just controls what it's called.
        chunkFileNames: (chunkInfo) => {
          if (chunkInfo.moduleIds?.some(id => id.includes('/routes/map'))) {
            return 'assets/map-[hash].js'
          }
          return 'assets/[name]-[hash].js'
        },
      },
    },
  },
})
