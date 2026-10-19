import {supabase} from '../lib/supabase'

export async function queueReceiptPrint({order,data,mode='all'}){
  if(!order?.id) throw new Error('Order is required for printing.')
  if(!data?.branch?.id) throw new Error('Branch is not available.')
  const {data:{user}}=await supabase.auth.getUser()
  const payload={
    template:'receipt',mode,
    branch:{id:data.branch.id,name:data.branch.name||'NEXA'},
    order:{...order,table_name:data.tables?.find(t=>t.id===order.table_id)?.name||null},
    items:order.pos_order_items||[],
    customer:order.pos_customers||null,
    printed_by:data.profile?.name||user?.email||'Staff',
    requested_at:new Date().toISOString()
  }
  const row={branch_id:data.branch.id,order_id:order.id,job_type:'receipt',printer_type:'receipt',status:'pending',payload,created_by:user?.id||null}
  const {data:job,error}=await supabase.from('pos_print_jobs').insert(row).select('id').single()
  if(error){
    if(['42P01','PGRST205'].includes(String(error.code||''))) throw new Error('Print queue is not installed. Run supabase/NEXA_BRANCH_PRINT_QUEUE.sql first.')
    throw new Error(error.message || 'Unable to queue receipt print.')
  }
  return job
}
