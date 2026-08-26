import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react'
import type { Session, User } from '@supabase/supabase-js'
import { isSupabaseConfigured, supabase } from '@/lib/supabase'
import { fetchMyPermissions, fetchMyCountries } from '@/features/admin/queries'

// Capture before the Supabase SDK clears the hash / query params on client init.
// Implicit flow: #access_token=...&type=invite; PKCE flow: ?code=...&type=invite
const isInviteFlow =
  typeof window !== 'undefined' && (
    new URLSearchParams(window.location.hash.slice(1)).get('type') === 'invite' ||
    new URLSearchParams(window.location.search).get('type') === 'invite'
  )

interface AuthContextValue {
  loading: boolean
  session: Session | null
  user: User | null
  isAdmin: boolean
  isCountryAdmin: boolean
  needsPasswordSet: boolean
  needsPasswordReset: boolean
  permissions: string[]
  permissionsLoaded: boolean
  hasPermission: (key: string) => boolean
  countries: string[]
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>
  signInWithGoogle: () => Promise<{ error: Error | null }>
  signOut: () => Promise<void>
  clearNeedsPasswordSet: () => void
  clearNeedsPasswordReset: () => void
}

const AuthContext = createContext<AuthContextValue | null>(null)

export function AuthProvider({ children }: { children: ReactNode }) {
  const [loading, setLoading] = useState(true)
  const [session, setSession] = useState<Session | null>(null)
  const [needsPasswordSet, setNeedsPasswordSet] = useState(false)
  const [needsPasswordReset, setNeedsPasswordReset] = useState(false)
  const [permissions, setPermissions] = useState<string[]>([])
  const [permissionsLoaded, setPermissionsLoaded] = useState(false)
  const [countries, setCountries]     = useState<string[]>([])

  useEffect(() => {
    if (!isSupabaseConfigured) {
      setLoading(false)
      return
    }

    supabase.auth.getSession().then(({ data }) => {
      setSession(data.session)
      if (isInviteFlow && data.session) {
        setNeedsPasswordSet(true)
      }
    }).catch(() => {
      // leave session null
    }).finally(() => {
      setLoading(false)
    })

    const { data: { subscription } } = supabase.auth.onAuthStateChange((event, newSession) => {
      setSession(newSession)
      if (event === 'PASSWORD_RECOVERY') {
        setNeedsPasswordReset(true)
      }
      if (isInviteFlow && event === 'SIGNED_IN' && newSession) {
        setNeedsPasswordSet(true)
      }
      if (event === 'SIGNED_OUT') {
        setPermissions([])
        setCountries([])
        window.location.replace('/login')
      }
    })

    return () => subscription.unsubscribe()
  }, [])

  const user: User | null = session?.user ?? null
  const isAdmin = user?.app_metadata?.['role'] === 'admin'
  const isCountryAdmin = user?.app_metadata?.['role'] === 'country_admin'

  // Load permissions and countries on session change
  useEffect(() => {
    setPermissionsLoaded(false)
    if (!user) {
      setPermissions([])
      setCountries([])
      setPermissionsLoaded(true)
      return
    }
    if (isAdmin) {
      setPermissions([])
      setCountries([])
      setPermissionsLoaded(true)  // admins bypass permission checks, immediately ready
      return
    }
    // Country admins bypass dashboard permission checks but need their countries loaded for scoping
    if (isCountryAdmin) {
      setPermissions([])
      fetchMyCountries().then(setCountries).catch(() => setCountries([]))
      setPermissionsLoaded(true)
      return
    }
    fetchMyPermissions()
      .then((data) => { setPermissions(data); setPermissionsLoaded(true) })
      .catch(() => { setPermissions([]); setPermissionsLoaded(true) })
    fetchMyCountries().then(setCountries).catch(() => setCountries([]))
  }, [user?.id, isAdmin, isCountryAdmin])

  const hasPermission = useCallback(
    (key: string) => !isSupabaseConfigured || isAdmin || isCountryAdmin || permissions.includes(key),
    [isAdmin, isCountryAdmin, permissions],
  )

  async function signIn(email: string, password: string) {
    if (!isSupabaseConfigured) {
      return { error: new Error('Supabase is not configured for this deployment.') }
    }
    const { error } = await supabase.auth.signInWithPassword({ email, password })
    return { error: error as Error | null }
  }

  async function signInWithGoogle() {
    if (!isSupabaseConfigured) {
      return { error: new Error('Supabase is not configured for this deployment.') }
    }
    const { error } = await supabase.auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: window.location.origin },
    })
    return { error: error as Error | null }
  }

  async function signOut() {
    if (!isSupabaseConfigured) return
    await supabase.auth.signOut()
  }

  function clearNeedsPasswordSet() {
    setNeedsPasswordSet(false)
  }

  function clearNeedsPasswordReset() {
    setNeedsPasswordReset(false)
  }

  return (
    <AuthContext.Provider value={{ loading, session, user, isAdmin, isCountryAdmin, needsPasswordSet, needsPasswordReset, permissions, permissionsLoaded, hasPermission, countries, signIn, signInWithGoogle, signOut, clearNeedsPasswordSet, clearNeedsPasswordReset }}>
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const ctx = useContext(AuthContext)
  if (!ctx) throw new Error('useAuth must be used within AuthProvider')
  return ctx
}
