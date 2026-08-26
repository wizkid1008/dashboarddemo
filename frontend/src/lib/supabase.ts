import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

export const isSupabaseConfigured = Boolean(supabaseUrl && supabaseAnonKey)

// Demo deployments point at a Supabase project holding fabricated data and are meant to be
// browsable without signing in. Setting VITE_DEMO_OPEN_ACCESS=true keeps the unauthenticated
// experience the demo had before it was connected -- no /login redirect, every dashlet visible --
// while still issuing real RPCs as the `anon` role. Never set this on a deployment holding real
// programme data: it makes every RPC granted to `anon` readable by anyone with the link.
export const isDemoOpenAccess =
  (import.meta.env.VITE_DEMO_OPEN_ACCESS as string | undefined) === 'true'

export const supabase = createClient(
  supabaseUrl || 'https://example.supabase.co',
  supabaseAnonKey || 'public-anon-key',
)
