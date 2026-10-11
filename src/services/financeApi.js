import { supabase } from '../lib/supabase';

const ok = (data, error) => { if (error) throw error; return data || []; };
export async function getFinanceDashboard(startDate,endDate){
  const {data,error}=await supabase.rpc('nexa_finance_dashboard',{p_start:startDate,p_end:endDate});
  if(error) throw error; return data?.[0]||data||{};
}
export async function getDailySales(startDate,endDate){
  const {data,error}=await supabase.rpc('nexa_daily_sales',{p_start:startDate,p_end:endDate}); return ok(data,error);
}
export async function getPaymentSummary(startDate,endDate){
  const {data,error}=await supabase.rpc('nexa_payment_summary',{p_start:startDate,p_end:endDate}); return ok(data,error);
}
export async function getExpenseSummary(startDate,endDate){
  const {data,error}=await supabase.rpc('nexa_expense_summary',{p_start:startDate,p_end:endDate}); return ok(data,error);
}
export async function getProfitLoss(startDate,endDate){
  const {data,error}=await supabase.rpc('nexa_profit_loss',{p_start:startDate,p_end:endDate}); return ok(data,error);
}
export async function getTaxSummary(startDate,endDate){
  const {data,error}=await supabase.rpc('nexa_tax_summary',{p_start:startDate,p_end:endDate}); return ok(data,error);
}
export async function getShiftSummary(startDate,endDate){
  const {data,error}=await supabase.rpc('nexa_shift_summary',{p_start:startDate,p_end:endDate}); return ok(data,error);
}
export async function addExpense(payload){
  const {data,error}=await supabase.from('expenses').insert(payload).select().single(); if(error) throw error; return data;
}
export async function listExpenses(startDate,endDate){
  const {data,error}=await supabase.from('expenses').select('*').gte('created_at',startDate+'T00:00:00').lte('created_at',endDate+'T23:59:59').order('created_at',{ascending:false}); return ok(data,error);
}
export function subscribeFinance(branchId,onChange){
  if(!branchId) return ()=>{};
  const c=supabase.channel('finance-'+branchId)
    .on('postgres_changes',{event:'*',schema:'public',table:'payments'},onChange)
    .on('postgres_changes',{event:'*',schema:'public',table:'expenses',filter:`branch_id=eq.${branchId}`},onChange)
    .on('postgres_changes',{event:'*',schema:'public',table:'shifts',filter:`branch_id=eq.${branchId}`},onChange).subscribe();
  return ()=>supabase.removeChannel(c);
}
