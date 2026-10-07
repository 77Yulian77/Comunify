import { supabase } from './api.js'

export async function adminLogin(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({
    email,
    password,
  })
  if (error) throw new Error(error.message)
  return data
}

export async function adminLogout() {
  await supabase.auth.signOut()
  localStorage.removeItem('comunify_admin_session')
  window.location.href = 'index.html'
}

export function getAdminSession() {
  const raw = localStorage.getItem('comunify_admin_session')
  if (!raw) return null
  try {
    const session = JSON.parse(raw)
    if (session.expires_at && Date.now() > session.expires_at) {
      localStorage.removeItem('comunify_admin_session')
      return null
    }
    return session
  } catch {
    return null
  }
}

export function setAdminSession(session) {
  const sessionData = {
    access_token: session.access_token,
    refresh_token: session.refresh_token,
    expires_at: session.expires_at ? session.expires_at * 1000 : Date.now() + 3600000,
    user: { email: session.user?.email },
  }
  localStorage.setItem('comunify_admin_session', JSON.stringify(sessionData))
}

export function requireAuth() {
  const session = getAdminSession()
  if (!session) {
    window.location.href = 'login.html'
    return false
  }
  return true
}

export async function getCurrentSession() {
  const { data } = await supabase.auth.getSession()
  return data.session
}
