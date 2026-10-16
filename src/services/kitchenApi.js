import { supabase } from '../lib/supabase'
const req=e=>{if(e)throw e}
export async function loadKitchen(branchId){
 if(!branchId)return {orders:[],departments:[],printers:[]}
 const [orders,depts,printers]=await Promise.all([
  supabase.from('orders').select('*, customers(name,phone,address), restaurant_tables(name), order_items(*)').eq('branch_id',branchId).not('status','in','("Completed","Cancelled","Draft")').order('created_at'),
  supabase.from('kitchen_departments').select('*').eq('branch_id',branchId).eq('active',true).order('name'),
  supabase.from('printer_settings').select('*').eq('branch_id',branchId).order('name')
 ]);[orders,depts,printers].forEach(x=>req(x.error));return{orders:orders.data||[],departments:depts.data||[],printers:printers.data||[]}
}
export async function setKitchenStatus(orderId,status){const patch={kitchen_status:status};if(status==='Prepared')patch.prepared_at=new Date().toISOString();if(status==='Served')patch.served_at=new Date().toISOString();const{error}=await supabase.from('orders').update(patch).eq('id',orderId);req(error)}
export async function setItemStatus(itemId,status){const{error}=await supabase.from('order_items').update({status,kitchen_updated_at:new Date().toISOString()}).eq('id',itemId);req(error)}
export async function createKot(order,branchId,userId){const{data,error}=await supabase.from('kitchen_tickets').insert({branch_id:branchId,order_id:order.id,token:order.token,status:'Processing',created_by:userId||null}).select().single();req(error);return data}
export async function logPrint({branchId,orderId,type='KOT',printerName='Default',userId}){const{error}=await supabase.from('print_jobs').insert({branch_id:branchId,order_id:orderId,job_type:type,printer_name:printerName,status:'Queued',created_by:userId||null});req(error)}
export function subscribeKitchen(branchId,onChange){if(!branchId)return()=>{};const ch=supabase.channel(`nexa-kitchen-${branchId}`).on('postgres_changes',{event:'*',schema:'public',table:'orders',filter:`branch_id=eq.${branchId}`},onChange).on('postgres_changes',{event:'*',schema:'public',table:'order_items'},onChange).subscribe();return()=>supabase.removeChannel(ch)}
