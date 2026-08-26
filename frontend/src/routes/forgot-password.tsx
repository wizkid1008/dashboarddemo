import { useState } from 'react'
import { Link } from '@tanstack/react-router'
import { supabase } from '@/lib/supabase'

export function ForgotPasswordPage() {
  const [email, setEmail] = useState('')
  const [sent, setSent] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [loading, setLoading] = useState(false)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    setLoading(true)
    const { error: resetError } = await supabase.auth.resetPasswordForEmail(email, {
      redirectTo: `${window.location.origin}/reset-password`,
    })
    setLoading(false)
    if (resetError) {
      setError(resetError.message)
    } else {
      setSent(true)
    }
  }

  return (
    <div className="login-page">
      <div className="login-card">
        <img src="/images/shf-logo-horizontal.jpg" alt="SHF Agriculture" className="login-logo" />
        <h1 className="login-title">Reset password</h1>
        <p className="login-subtitle">Enter your email and we'll send you a reset link.</p>

        {sent ? (
          <div>
            <p className="login-subtitle" style={{ marginTop: '1rem' }}>
              Check your inbox for a password reset link. You can close this tab.
            </p>
            <Link to="/login" className="login-btn" style={{ display: 'block', textAlign: 'center', marginTop: '1.5rem' }}>
              Back to sign in
            </Link>
          </div>
        ) : (
          <form onSubmit={handleSubmit} className="login-form">
            <div className="login-field">
              <label htmlFor="email">Email</label>
              <input
                id="email"
                type="email"
                autoComplete="email"
                required
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                placeholder="you@example.com"
              />
            </div>

            {error && <p className="login-error">{error}</p>}

            <button type="submit" className="login-btn" disabled={loading}>
              {loading ? 'Sending…' : 'Send reset link'}
            </button>

            <Link to="/login" className="login-forgot">
              Back to sign in
            </Link>
          </form>
        )}
      </div>
    </div>
  )
}
