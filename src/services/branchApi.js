import {supabase} from '../lib/supabase'
const req=e=>{if(e)throw e}
export async function listBranches(){const{data,error}=await supabase.from('branches').select('id,name,address,phone,active,created_at').order('name');req(error);return data||[]}
export async function saveBranch(row){const{data,error}=await supabase.rpc('nexa_developer_save_branch',{p_id:row.id||null,p_name:row.name,p_address:row.address||null,p_phone:row.phone||null,p_active:row.active!==false});req(error);return data}

export async function deleteBranch(id){const{data,error}=await supabase.rpc('nexa_developer_delete_branch',{p_branch_id:id});req(error);return data}
