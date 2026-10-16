import {supabase} from '../lib/supabase'
const req=e=>{if(e)throw e}
export async function loadExpenses(branchId){let q=supabase.from('expenses').select('*').order('created_at',{ascending:false}).limit(100);if(branchId)q=q.eq('branch_id',branchId);const{data,error}=await q;req(error);return data||[]}
export async function createExpense({category,description,amount}){const{data,error}=await supabase.rpc('nexa_create_expense',{p_category:category,p_description:description||null,p_amount:Number(amount)});req(error);return data}
