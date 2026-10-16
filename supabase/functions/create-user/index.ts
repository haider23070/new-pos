import {createClient} from 'https://esm.sh/@supabase/supabase-js@2'
Deno.serve(async(req)=>{
  const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
  try{
    const url=Deno.env.get('SUPABASE_URL')!, service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, anon=Deno.env.get('SUPABASE_ANON_KEY')!
    const token=req.headers.get('Authorization')||''
    const caller=createClient(url,anon,{global:{headers:{Authorization:token}}})
    const {data:{user}}=await caller.auth.getUser(); if(!user)throw new Error('Unauthorized')
    const admin=createClient(url,service)
    const {data:me}=await admin.from('users').select('id,branch_id,role,user_roles(roles(name))').eq('auth_id',user.id).single()
    const callerRole=me?.user_roles?.[0]?.roles?.name||me?.role
    if(!['Developer','Admin','Manager'].includes(callerRole))throw new Error('Not allowed to create users')
    const body=await req.json(); const {email,password,name,phone,branch_id,role}=body
    if(callerRole!=='Developer' && branch_id!==me.branch_id)throw new Error('Cannot create users in another branch')
    if(role==='Developer' && callerRole!=='Developer')throw new Error('Only Developer can assign Developer role')
    const {data:created,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{name}});if(error)throw error
    const {data:profile,error:pe}=await admin.from('users').insert({auth_id:created.user.id,email,name,full_name:name,phone,branch_id,role,status:'Active'}).select().single();if(pe)throw pe
    const {data:r}=await admin.from('roles').select('id').eq('name',role).single();if(r)await admin.from('user_roles').insert({user_id:profile.id,role_id:r.id})
    return new Response(JSON.stringify({user:profile}),{headers:{...cors,'Content-Type':'application/json'}})
  }catch(e){return new Response(JSON.stringify({error:e.message}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
})
