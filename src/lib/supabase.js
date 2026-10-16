import {createClient} from '@supabase/supabase-js'
const url=import.meta.env.VITE_SUPABASE_URL
const key=import.meta.env.VITE_SUPABASE_ANON_KEY
export const configured=Boolean(url&&key&&!url.includes('YOUR_PROJECT'))
export const supabase=configured?createClient(url,key,{auth:{persistSession:true,autoRefreshToken:true}}):null
export async function requireUser(){if(!supabase)throw new Error('Supabase is not configured. Copy .env.example to .env and add your project URL and anon key.');const {data:{user},error}=await supabase.auth.getUser();if(error)throw error;return user}

// Verify an Admin/Manager password without replacing the cashier's active POS session.
export async function verifyManagementPassword(profileId,password){
  if(!supabase) throw new Error('Supabase is not configured.')
  if(!profileId||!password) throw new Error('Select an Admin/Manager and enter their password.')
  const {data:profile,error:profileError}=await supabase.from('pos_profiles').select('id,email,name,role,active').eq('id',profileId).maybeSingle()
  if(profileError) throw profileError
  if(!profile||profile.active===false) throw new Error('Selected authorizer is not active.')
  const role=String(profile.role||'').trim().toLowerCase().replace(/[ _-]+/g,'')
  if(!['admin','manager'].includes(role)) throw new Error('Only Admin or Manager can authorize a discount.')
  const verifier=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false,detectSessionInUrl:false}})
  const {data,error}=await verifier.auth.signInWithPassword({email:profile.email,password})
  if(error) throw new Error('Incorrect Admin/Manager password.')
  if(data.user?.id!==profile.id){await verifier.auth.signOut();throw new Error('Password does not match the selected Admin/Manager.')}
  await verifier.auth.signOut()
  return profile
}
