import {supabase} from '../lib/supabase'
const req=(e)=>{if(e)throw e}
export async function loadDashboard(branchId){
 if(!branchId)return {orders:[],payments:[],ingredients:[],riders:[]}
 const since=new Date(); since.setHours(0,0,0,0)
 const [orders,payments,ingredients,riders]=await Promise.all([
  supabase.from('orders').select('id,status,kitchen_status,order_type,grand_total,created_at').eq('branch_id',branchId).gte('created_at',since.toISOString()).order('created_at',{ascending:false}),
  supabase.from('payments').select('id,amount,status,created_at,orders!inner(branch_id)').eq('orders.branch_id',branchId).gte('created_at',since.toISOString()),
  supabase.from('inventory_ingredients').select('id,name,current_stock,min_stock,unit').eq('branch_id',branchId).eq('active',true),
  supabase.from('riders').select('id,profile_id,branch_id,on_duty,cash_balance').eq('branch_id',branchId)
 ]); [orders,payments,ingredients,riders].forEach(x=>req(x.error));
 const ids=(riders.data||[]).map(r=>r.profile_id).filter(Boolean); let profiles=[];
 if(ids.length){const pr=await supabase.from('profiles').select('id,name,email').in('id',ids);req(pr.error);profiles=pr.data||[]}
 const riderRows=(riders.data||[]).map(r=>{const p=profiles.find(x=>x.id===r.profile_id);return {...r,name:p?.name||'Rider',email:p?.email||'',status:r.on_duty?'Available':'Off Duty'}});
 return {orders:orders.data||[],payments:payments.data||[],ingredients:ingredients.data||[],riders:riderRows}
}
