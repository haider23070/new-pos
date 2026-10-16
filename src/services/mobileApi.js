import {supabase} from '../lib/supabase'
const req=e=>{if(e)throw e}
export async function riderBootstrap(branchId){
 const {data:{user}}=await supabase.auth.getUser(); if(!user)return {rider:null,deliveries:[],attendance:null,location:null}
 const {data:rider,error:rErr}=await supabase.from('riders').select('id,profile_id,branch_id,on_duty,cash_balance').eq('profile_id',user.id).eq('branch_id',branchId).maybeSingle();req(rErr)
 if(!rider)return {rider:null,deliveries:[],attendance:null,location:null}
 const [d,a,l]=await Promise.all([
  supabase.from('deliveries').select('*,orders(id,token,invoice_no,status,kitchen_status,grand_total,created_at,customers(name,phone,address),order_items(name,qty))').eq('rider_id',rider.id).order('assigned_at',{ascending:false}).limit(50),
  supabase.from('rider_attendance').select('*').eq('rider_id',rider.id).order('started_at',{ascending:false}).limit(1).maybeSingle(),
  supabase.from('rider_locations').select('*').eq('rider_id',rider.id).order('recorded_at',{ascending:false}).limit(1).maybeSingle()
 ]);[d,a,l].forEach(x=>req(x.error));return {rider,deliveries:d.data||[],attendance:a.data||null,location:l.data||null}
}
export async function startRiderShift(riderId,branchId,lat,lng){const {data,error}=await supabase.rpc('nexa_rider_start_shift',{p_rider_id:riderId,p_lat:lat,p_lng:lng});req(error);return data}
export async function endRiderShift(riderId){const {error}=await supabase.rpc('nexa_rider_end_shift',{p_rider_id:riderId});req(error)}
export async function pushRiderLocation(riderId,branchId,lat,lng,accuracy){const {error}=await supabase.rpc('nexa_rider_push_location',{p_rider_id:riderId,p_lat:lat,p_lng:lng,p_accuracy_m:accuracy||null});req(error)}
export async function riderDeliveryStatus(id,status){const {error}=await supabase.rpc('nexa_rider_delivery_status',{p_delivery_id:id,p_status:status});req(error)}
export async function orderTakerOrders(branchId){const {data:{user}}=await supabase.auth.getUser();const {data,error}=await supabase.from('orders').select('*,customers(name,phone),order_items(name,qty)').eq('branch_id',branchId).eq('created_by',user?.id).neq('order_type','Delivery').order('created_at',{ascending:false}).limit(100);req(error);return data||[]}
export async function publicBranches(){const {data,error}=await supabase.rpc('nexa_public_branches');req(error);return data||[]}
export async function publicMenu(branchId){const {data,error}=await supabase.rpc('nexa_public_menu',{p_branch_id:branchId});req(error);return data||[]}
export async function publicPlaceOrder(payload){const {data,error}=await supabase.rpc('nexa_public_place_order',{p_branch_id:payload.branchId,p_customer_name:payload.name,p_phone:payload.phone,p_address:payload.address,p_items:payload.items});req(error);return data}
export async function publicTrackOrder(code,phone){const {data,error}=await supabase.rpc('nexa_public_track_order',{p_code:code,p_phone:phone});req(error);return data?.[0]||data||null}
export async function getBranchLocation(branchId){const {data,error}=await supabase.from('branches').select('id,name,address,latitude,longitude,attendance_radius_m,delivery_radius_km').eq('id',branchId).single();req(error);return data}
export async function saveBranchLocation(branchId,latitude,longitude,attendanceRadius=500,deliveryRadius=8){
 const lat=Number(latitude),lng=Number(longitude),attendance=Number(attendanceRadius||500),delivery=Number(deliveryRadius||8)
 if(!branchId)throw new Error('Branch is required')
 if(!Number.isFinite(lat)||lat < -90||lat > 90)throw new Error('Enter a valid latitude')
 if(!Number.isFinite(lng)||lng < -180||lng > 180)throw new Error('Enter a valid longitude')
 const {data,error}=await supabase.rpc('nexa_save_branch_location',{p_branch_id:branchId,p_latitude:lat,p_longitude:lng,p_attendance_radius_m:attendance,p_delivery_radius_km:delivery});req(error)
 const saved=await getBranchLocation(branchId)
 if(saved.latitude==null||saved.longitude==null)throw new Error('Location was not persisted. Please try again.')
 return saved
}
