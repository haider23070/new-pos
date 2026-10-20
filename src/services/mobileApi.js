import {supabase} from '../lib/supabase'
const req=e=>{if(e)throw e}
export async function riderBootstrap(branchId){
 const {data:{user}}=await supabase.auth.getUser(); if(!user)return {rider:null,deliveries:[],attendance:null,location:null}
 // Exact NEXA schema: pos_riders.profile_id -> pos_profiles.id/auth.users.id.
 let r=await supabase.from('pos_riders').select('*').eq('profile_id',user.id).eq('branch_id',branchId).eq('active',true).maybeSingle();req(r.error)
 // Self-heal older rider records that were created before profile_id linking existed.
 if(!r.data){
  const link=await supabase.rpc('nexa_pos_link_current_rider');
  if(link.error) throw new Error(link.error.message||'This login is not linked to a rider record.');
  r=await supabase.from('pos_riders').select('*').eq('profile_id',user.id).eq('branch_id',branchId).eq('active',true).maybeSingle();req(r.error)
 }
 const rider=r.data||null
 if(!rider)return {rider:null,deliveries:[],attendance:null,location:null}
 const [o,a,l]=await Promise.all([
  supabase.from('pos_orders').select('*').eq('branch_id',branchId).eq('rider_id',rider.id).eq('order_type','Delivery').order('created_at',{ascending:false}).limit(50),
  supabase.from('pos_rider_attendance').select('*').eq('rider_id',rider.id).order('started_at',{ascending:false}).limit(1).maybeSingle(),
  supabase.from('pos_rider_locations').select('*').eq('rider_id',rider.id).order('recorded_at',{ascending:false}).limit(1).maybeSingle()
 ]);[o,a,l].forEach(x=>req(x.error));
 const orders=o.data||[], customerIds=[...new Set(orders.map(x=>x.customer_id).filter(Boolean))], orderIds=orders.map(x=>x.id)
 const [cs,it]=await Promise.all([
  customerIds.length?supabase.from('pos_customers').select('*').in('id',customerIds):Promise.resolve({data:[],error:null}),
  orderIds.length?supabase.from('pos_order_items').select('*').in('order_id',orderIds):Promise.resolve({data:[],error:null})
 ]);req(cs.error);req(it.error)
 const customers=Object.fromEntries((cs.data||[]).map(x=>[x.id,x]));
 const deliveries=orders.map(x=>({id:x.id,status:x.delivery_status||'Assigned',delivery_address:x.delivery_address,orders:{...x,token:x.token_no||x.token,customers:customers[x.customer_id]||null,order_items:(it.data||[]).filter(i=>i.order_id===x.id)}}))
 return {rider,deliveries,attendance:a.data||null,location:l.data||null}
}
export async function startRiderShift(riderId,branchId,lat,lng){
 const {data,error}=await supabase.rpc('nexa_pos_rider_check_in',{p_rider_id:riderId,p_lat:lat,p_lng:lng,p_accuracy:null});req(error);return data
}
export async function endRiderShift(riderId){const {error}=await supabase.rpc('nexa_pos_rider_check_out',{p_rider_id:riderId});req(error)}
export async function pushRiderLocation(riderId,branchId,lat,lng,accuracy){const {error}=await supabase.rpc('nexa_pos_rider_push_location',{p_rider_id:riderId,p_lat:lat,p_lng:lng,p_accuracy:accuracy||null});req(error)}
export async function riderDeliveryStatus(id,status){const mapped=status==='Picked'?'PICKED':status==='Delivered'?'DELIVERED':String(status).toUpperCase().replaceAll(' ','_');const patch={delivery_status:mapped};if(mapped==='DELIVERED')patch.completed_at=new Date().toISOString();const {error}=await supabase.from('pos_orders').update(patch).eq('id',id);req(error)}
