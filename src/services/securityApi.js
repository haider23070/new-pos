import {supabase} from '../lib/supabase'
const rpc=async(name,args)=>{const {data,error}=await supabase.rpc(name,args);if(error)throw error;return data}
export const authorizeManagerPin=(pin,action,entityType=null,entityId=null,reason=null)=>rpc('nexa_authorize_manager_pin',{p_pin:pin,p_action:action,p_entity_type:entityType,p_entity_id:entityId,p_reason:reason})
export const reversePayment=(paymentId,reason,pin)=>rpc('nexa_reverse_payment',{p_payment_id:paymentId,p_reason:reason,p_manager_pin:pin})
export const secureCloseShift=(shiftId,actualCash,pin,note='')=>rpc('nexa_secure_close_shift',{p_shift_id:shiftId,p_actual_cash:Number(actualCash||0),p_manager_pin:pin,p_note:note})
export async function loadSecurityAudit(branchId,limit=100){
 const {data,error}=await supabase.from('audit_log').select('*').eq('branch_id',branchId).order('created_at',{ascending:false}).limit(limit);if(error)throw error;return data||[]
}
