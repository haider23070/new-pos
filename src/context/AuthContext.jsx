import React, {createContext,useCallback,useContext,useEffect,useMemo,useState} from 'react'
import {supabase,isSupabaseConfigured} from '../lib/supabase'
import {can,normalizeRole} from '../auth/permissions'

const AuthContext=createContext(null)

export function AuthProvider({children}){
  const [session,setSession]=useState(null)
  const [profile,setProfile]=useState(null)
  const [loading,setLoading]=useState(true)

  const loadProfile=useCallback(async(user)=>{
    if(!supabase||!user){setProfile(null);return null}

    // NEXA's current schema stores the login profile in public.profiles with
    // profiles.id = auth.users.id. Older builds used public.users/auth_id.
    // Read profiles first so a valid Admin never falls back to the UI "User" label.
    const {data:profileRow,error:profileError}=await supabase
      .from('profiles')
      .select('*')
      .eq('id',user.id)
      .maybeSingle()

    if(profileError) console.warn('Could not load public.profiles:',profileError.message)

    let legacyUser=null
    if(!profileRow){
      const {data,error}=await supabase
        .from('users')
        .select('*')
        .eq('auth_id',user.id)
        .maybeSingle()
      if(error) console.warn('Could not load legacy public.users:',error.message)
      legacyUser=data||null
    }

    const base=profileRow||legacyUser||{}
    const metadataRole=user.app_metadata?.role||user.user_metadata?.role
    const role=normalizeRole(base.role||metadataRole||'Cashier')
    const resolved={
      ...base,
      id:base.id||user.id,
      auth_id:base.auth_id||user.id,
      email:base.email||user.email,
      name:base.name||base.full_name||user.user_metadata?.name||user.email,
      role,
      active:base.active!==false,
      user_permissions:base.user_permissions||[],
    }
    setProfile(resolved)
    return resolved
  },[])

  useEffect(()=>{
    if(!supabase){setLoading(false);return}
    let alive=true
    const init=async()=>{
      try{
        const {data}=await supabase.auth.getSession()
        if(!alive)return
        setSession(data.session)
        if(data.session)await loadProfile(data.session.user)
        else setProfile(null)
      }catch(e){console.error('Auth initialization failed:',e)}
      finally{if(alive)setLoading(false)}
    }
    init()
    const {data:sub}=supabase.auth.onAuthStateChange((_event,s)=>{
      setSession(s)
      if(!s){setProfile(null);setLoading(false);return}
      // Do not await Supabase queries inside the auth callback; schedule profile load.
      setTimeout(()=>loadProfile(s.user).catch(e=>console.error('Profile refresh failed:',e)).finally(()=>setLoading(false)),0)
    })
    return()=>{alive=false;sub.subscription.unsubscribe()}
  },[loadProfile])

  const signIn=async(email,password)=>{
    if(!supabase)throw new Error('Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY to .env.')
    const {data,error}=await supabase.auth.signInWithPassword({email,password})
    if(error)throw error
    if(data?.user)await loadProfile(data.user)
    return data
  }
  const signOut=()=>supabase?.auth.signOut()
  const hasPermission=(p)=>can(profile?.role,p,profile?.user_permissions||[])
  const value=useMemo(()=>({session,user:session?.user||null,profile,loading,signIn,signOut,hasPermission,isSupabaseConfigured}),[session,profile,loading])
  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}
export const useAuth=()=>useContext(AuthContext)
