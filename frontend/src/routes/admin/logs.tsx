import { useEffect } from 'react'
import { useNavigate } from '@tanstack/react-router'

export function AdminLogsPage() {
  const navigate = useNavigate()
  useEffect(() => { void navigate({ to: '/admin/ingest' }) }, [navigate])
  return null
}
