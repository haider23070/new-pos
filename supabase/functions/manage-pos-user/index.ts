import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
Deno.serve(async (req) => {
  const cors={'Access-Control-Allow-Origin':'*','Access-Control-Allow-Headers':'authorization, x-client-info, apikey, content-type'}
  if(req.method==='OPTIONS')return new Response('ok',{headers:cors})
  try{
    const url=Deno.env.get('SUPABASE_URL')!, anon=Deno.env.get('SUPABASE_ANON_KEY')!, service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const auth=req.headers.get('Authorization')||''
    const caller=createClient(url,anon,{global:{headers:{Authorization:auth}}})
    const admin=createClient(url,service,{auth:{autoRefreshToken:false,persistSession:false}})
    const {data:{user},error:ue}=await caller.auth.getUser(); if(ue||!user)throw new Error('Not authenticated.')
    const {data:me,error:pe}=await admin.from('pos_profiles').select('role,branch_id,active').eq('id',user.id).single(); if(pe)throw pe
    if(me.active===false||!['Admin','Manager'].includes(me.role))throw new Error('Only Admin or Manager can manage employees.')
    const body=await req.json()
    if(body.action==='create'){
      if(body.branch_id!==me.branch_id&&me.role!=='Admin')throw new Error('Manager can only create users in their branch.')
      const {data:created,error:e}=await admin.auth.admin.createUser({email:body.email,password:body.password,email_confirm:true,user_metadata:{name:body.name}}); if(e)throw e
      const {error:p}=await admin.from('pos_profiles').upsert({id:created.user.id,email:body.email,name:body.name,role:body.role,branch_id:body.branch_id,active:body.active!==false,receipt_printer_name:body.receipt_printer_name||null}); if(p){await admin.auth.admin.deleteUser(created.user.id);throw p}
      return new Response(JSON.stringify({ok:true,id:created.user.id}),{headers:{...cors,'Content-Type':'application/json'}})
    }
    if(body.action==='password'){
      const {data:target}=await admin.from('pos_profiles').select('branch_id').eq('id',body.user_id).single(); if(!target||target.branch_id!==me.branch_id)throw new Error('User is outside your branch.')
      const {error:e}=await admin.auth.admin.updateUserById(body.user_id,{password:body.password}); if(e)throw e
      return new Response(JSON.stringify({ok:true}),{headers:{...cors,'Content-Type':'application/json'}})
    }
    throw new Error('Unsupported action.')
  }catch(e){return new Response(JSON.stringify({error:e.message||String(e)}),{status:400,headers:{...cors,'Content-Type':'application/json'}})}
})
