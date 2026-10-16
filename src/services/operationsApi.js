import {supabase,isSupabaseConfigured} from '../lib/supabase'
import {secureCloseShift} from './securityApi'
const need=()=>{if(!isSupabaseConfigured||!supabase) throw new Error('Supabase is not configured')}
export async function loadOperations(branchId){
 if(!isSupabaseConfigured||!supabase) return {tables:[],riders:[],deliveries:[],shift:null,movements:[]}
 const [t,r,d,deliveryOrders,s]=await Promise.all([
  supabase.from('restaurant_tables').select('*').eq('branch_id',branchId).order('name'),
  supabase.from('riders').select('id,profile_id,branch_id,on_duty,cash_balance').eq('branch_id',branchId),
  supabase.from('deliveries').select('*,orders(id,token,invoice_no,grand_total,status,kitchen_status,delivery_status,order_type,created_at,customer_id)').eq('branch_id',branchId).order('assigned_at',{ascending:false}).limit(150),
  supabase.from('orders').select('id,branch_id,token,invoice_no,grand_total,status,kitchen_status,delivery_status,order_type,created_at,customer_id,customers(name,phone,address)').eq('branch_id',branchId).ilike('order_type','%Delivery%').neq('status','Draft').neq('status','Cancelled').order('created_at',{ascending:false}).limit(150),
  supabase.from('shifts').select('*').eq('branch_id',branchId).ilike('status','open').order('opened_at',{ascending:false}).limit(1).maybeSingle()
 ]); for(const x of [t,r,d,deliveryOrders,s]) if(x.error) throw x.error
 const profileIds=(r.data||[]).map(x=>x.profile_id).filter(Boolean); let riderProfiles=[]; if(profileIds.length){const pr=await supabase.from('profiles').select('id,name,email').in('id',profileIds);if(pr.error)throw pr.error;riderProfiles=pr.data||[]}
 const riderRows=(r.data||[]).map(x=>{const p=riderProfiles.find(y=>y.id===x.profile_id);return {...x,name:p?.name||'Rider',email:p?.email||'',phone:'',status:x.on_duty?'Available':'Off Duty'}});
 let movements=[]; if(s.data){const m=await supabase.from('cash_movements').select('*').eq('shift_id',s.data.id).order('created_at',{ascending:false}); if(m.error)throw m.error;movements=m.data||[]}
 const live=await supabase.rpc('nexa_live_riders'); if(live.error) throw live.error;
 const queue=d.data||[], byOrder=new Map(queue.map(x=>[x.order_id,x]));
 const merged=[...queue.filter(x=>String(x.orders?.status||'').toLowerCase()!=='cancelled')];
 for(const o of (deliveryOrders.data||[])){if(!byOrder.has(o.id)){merged.push({id:`order-${o.id}`,queue_id:null,order_id:o.id,branch_id:o.branch_id,customer_name:o.customers?.name||'Delivery Customer',customer_phone:o.customers?.phone||'',delivery_address:o.customers?.address||'',status:o.delivery_status||'Awaiting Rider',rider_id:null,orders:o,_missingQueue:true})}}
 merged.sort((a,b)=>new Date(b.orders?.created_at||b.assigned_at||0)-new Date(a.orders?.created_at||a.assigned_at||0));
 return {tables:t.data||[],riders:riderRows,liveRiders:live.data||[],deliveries:merged,shift:s.data||null,movements}
}
export async function setTableStatus(id,status,orderId=null){need();const patch={status};if('occupied_order_id' in patch)patch.occupied_order_id=orderId;const {error}=await supabase.from('restaurant_tables').update(patch).eq('id',id);if(error)throw error}
export async function setRiderDuty(id,on){need();const {error}=await supabase.from('riders').update({on_duty:on}).eq('id',id);if(error)throw error}
export async function assignRider(deliveryId,riderId,orderId=null){need();let id=deliveryId;if(!id||String(id).startsWith('order-')){const q=await supabase.rpc('nexa_ensure_delivery_queue',{p_order_id:orderId||String(deliveryId).replace('order-','')});if(q.error)throw q.error;id=q.data}const {error}=await supabase.rpc('nexa_assign_rider',{p_delivery_id:id,p_rider_id:riderId});if(error)throw error}
export async function deliveryAction(id,status,orderId=null){need();if(!id||String(id).startsWith('order-')){const q=await supabase.rpc('nexa_ensure_delivery_queue',{p_order_id:orderId||String(id).replace('order-','')});if(q.error)throw q.error;id=q.data}const {error}=await supabase.rpc('nexa_delivery_transition',{p_delivery_id:id,p_status:status});if(error)throw error}
export async function createRestaurantTable(branchId,name,seats=4,floorName='Main Floor'){need();const {data,error}=await supabase.rpc('nexa_admin_create_table',{p_branch_id:branchId,p_name:name,p_seats:Number(seats||4),p_floor_name:floorName||'Main Floor'});if(error)throw error;return data}
export async function openShift(branchId,_userId,openingCash){need();const {data:{user}}=await supabase.auth.getUser();const {data,error}=await supabase.from('shifts').insert({branch_id:branchId,opened_by:user?.id||null,opening_cash:Number(openingCash||0),status:'Open'}).select().single();if(error)throw error;return data}
export async function cashMovement(branchId,shiftId,_userId,type,amount,notes=''){need();const map={'Cash In':'cash_in','Cash Out':'cash_out','Expense':'expense'};const {data:{user}}=await supabase.auth.getUser();const {error}=await supabase.from('cash_movements').insert({branch_id:branchId,shift_id:shiftId,created_by:user?.id||null,type:map[type]||String(type).toLowerCase(),amount:Number(amount||0),notes});if(error)throw error}
export async function closeShift(shift,actualCash,_handoverTo,note='',pin=''){need();if(!pin)throw new Error('Manager PIN is required');return secureCloseShift(shift.id,actualCash,pin,note)}
export function subscribeOperations(branchId,onChange){if(!supabase)return()=>{};const ch=supabase.channel('p8-ops-'+branchId);for(const table of ['restaurant_tables','riders','deliveries','orders','shifts','cash_movements'])ch.on('postgres_changes',{event:'*',schema:'public',table,filter:`branch_id=eq.${branchId}`},onChange);ch.subscribe();return()=>supabase.removeChannel(ch)}
