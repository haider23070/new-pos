import { supabase } from '../lib/supabase'

const req = (error) => { if (error) throw error }
export async function loadPosBootstrap(branchId){
  if(!branchId) return {categories:[],items:[],customers:[],tables:[],orders:[]}
  const [cats,items,customers,tables,orders] = await Promise.all([
    supabase.from('categories').select('*').eq('branch_id',branchId).eq('active',true).order('sort_order'),
    supabase.from('menu_items').select('*, menu_variants(*)').eq('branch_id',branchId).eq('active',true).order('name'),
    supabase.from('customers').select('*').eq('branch_id',branchId).order('name').limit(250),
    supabase.from('restaurant_tables').select('*').eq('branch_id',branchId).order('name'),
    supabase.from('orders').select('*, customers(name,phone,address), restaurant_tables(name), order_items(*)').eq('branch_id',branchId).order('created_at',{ascending:false}).limit(150),
  ])
  ;[cats,items,customers,tables,orders].forEach(x=>req(x.error))
  return {categories:cats.data||[],items:items.data||[],customers:customers.data||[],tables:tables.data||[],orders:orders.data||[]}
}
export async function createCustomer(branchId,input){
  const {data,error}=await supabase.from('customers').insert({branch_id:branchId,...input}).select().single(); req(error); return data
}
export async function saveOrder({branchId,userId,shiftId,customerId,tableId,type,cart,discount=0,tax=0,status='Placed',notes=''}){
  if(!cart.length) throw new Error('Add at least one item')
  const items=cart.map(x=>({variant_id:x.variant_id||null,qty:Number(x.qty),notes:x.notes||null}))
  const {data,error}=await supabase.rpc('nexa_create_order',{p_order_type:type,p_customer_id:customerId||null,p_table_id:tableId||null,p_shift_id:shiftId||null,p_items:items,p_discount:Number(discount||0),p_tax:Number(tax||0),p_notes:notes||null,p_draft:status==='Draft'})
  req(error); return {id:data}
}
export async function updateOrderStatus(orderId,status,extra={}){const {error}=await supabase.from('orders').update({status,...extra}).eq('id',orderId);req(error)}
export async function cancelOrder(orderId,reason,managerPin=null){const {error}=await supabase.rpc('nexa_secure_cancel_order',{p_order_id:orderId,p_reason:reason,p_manager_pin:managerPin});req(error)}
export async function payOrder(orderId,userId,payments){
  const rows=payments.filter(x=>+x.amount>0).map(x=>({method:x.method,amount:+x.amount}))
  if(!rows.length) throw new Error('Enter payment amount')
  const {error}=await supabase.rpc('nexa_pay_order',{p_order_id:orderId,p_payments:rows});req(error)
}
export function subscribeOrders(branchId,onChange){
  if(!branchId)return()=>{}
  const ch=supabase.channel(`nexa-pos-${branchId}`).on('postgres_changes',{event:'*',schema:'public',table:'orders',filter:`branch_id=eq.${branchId}`},onChange).subscribe()
  return()=>supabase.removeChannel(ch)
}
export async function adminMarkOrderUnpaid(orderId,reason){
  const {error}=await supabase.rpc('nexa_admin_mark_order_unpaid',{p_order_id:orderId,p_reason:reason});req(error)
}

export async function updateOrder(orderId,{customerId,tableId,type,cart,discount=0,tax=0,notes=''}){
 if(!cart?.length) throw new Error('Order must contain at least one item')
 const subtotal=cart.reduce((s,x)=>s+Number(x.qty)*Number(x.unit_price),0), grand=Math.max(0,subtotal-Number(discount||0)+Number(tax||0))
 const {error}=await supabase.from('orders').update({customer_id:customerId||null,table_id:tableId||null,order_type:type,total:subtotal,discount:Number(discount||0),tax:Number(tax||0),grand_total:grand,notes}).eq('id',orderId);req(error)
 const {error:del}=await supabase.from('order_items').delete().eq('order_id',orderId);req(del)
 const rows=cart.map(x=>({order_id:orderId,item_id:x.item_id||null,variant_id:x.variant_id||null,name:x.name,qty:Number(x.qty),unit_price:Number(x.unit_price),status:x.status||'Pending',notes:x.notes||null}))
 const {error:ins}=await supabase.from('order_items').insert(rows);req(ins);return true
}
export async function updateOrderDiscount(orderId,discount){
 const {data:o,error:e}=await supabase.from('orders').select('total,tax').eq('id',orderId).single();req(e);const d=Math.max(0,Number(discount||0)),grand=Math.max(0,Number(o.total||0)-d+Number(o.tax||0));const {error}=await supabase.from('orders').update({discount:d,grand_total:grand}).eq('id',orderId);req(error)
}
