import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import './brand.css'
import './index.css'
import { QueryClientProvider } from '@tanstack/react-query'
import { RouterProvider } from '@tanstack/react-router'
import { queryClient } from './queryClient'
import { router } from './router'
import { AuthProvider, useAuth } from './contexts/AuthContext'

function InnerApp() {
  const auth = useAuth()
  if (auth.loading) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh' }}>
        <span style={{ color: '#6b7280', fontSize: '14px' }}>Loading…</span>
      </div>
    )
  }
  return <RouterProvider router={router} context={{ auth }} />
}

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <InnerApp />
      </AuthProvider>
    </QueryClientProvider>
  </StrictMode>,
)
