import{ supabase }from'../lib/supabase';const req=e=>{if(e)throw e};
export async function loadPrinterChoices(branchId){const{data,error}=await supabase.from('printer_settings').select('id,name,printer_name,department_id,active').eq('branch_id',branchId).eq('active',true).order('name');req(error);return data||[]}
export async function saveMyPreferences({receiptPrinter,theme}){const{error}=await supabase.from('profiles').update({receipt_printer_name:receiptPrinter||null,theme}).eq('id',(await supabase.auth.getUser()).data.user.id);req(error)}
export async function queueReceipt(orderId){const{error}=await supabase.rpc('nexa_queue_receipt',{p_order_id:orderId});req(error)}
