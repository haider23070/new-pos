import {supabase} from '../lib/supabase'
const req=e=>{if(e)throw e}
export async function loadStaff(_branchId,allBranches=false){
 const {data,error}=await supabase.rpc('nexa_staff_list',{p_all_branches:!!allBranches})
 req(error)
 return data||[]
}
export async function updateStaff(id,patch){const {data,error}=await supabase.rpc('nexa_update_staff_profile',{p_id:id,p_patch:patch});req(error);return data}
export async function createStaff(input){const {data,error}=await supabase.functions.invoke('create-staff',{body:input});if(error){const msg=String(error.message||error);if(/Failed to send a request|FunctionsFetchError|fetch/i.test(msg))throw new Error('Staff service is not deployed or cannot be reached. Deploy the Supabase Edge Function “create-staff”, then try again.');throw error}if(data?.error)throw new Error(data.error);return data}
