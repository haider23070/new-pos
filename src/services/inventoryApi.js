import { supabase } from '../lib/supabase'

const fail = (error) => { if (error) throw error }
export async function loadInventory(){
  const [ingredients,categories,recipes,suppliers,purchases,movements,wastage,transfers,closings] = await Promise.all([
    supabase.from('inventory_ingredients').select('*').order('name'),
    supabase.from('inventory_categories').select('*').order('name'),
    supabase.from('inventory_recipes').select('*, inventory_recipe_items(*)').order('name'),
    supabase.from('suppliers').select('*').order('name'),
    supabase.from('inventory_purchases').select('*, inventory_purchase_items(*)').order('created_at',{ascending:false}).limit(50),
    supabase.from('inventory_movements').select('*').order('created_at',{ascending:false}).limit(100),
    supabase.from('inventory_wastage').select('*').order('created_at',{ascending:false}).limit(50),
    supabase.from('inventory_transfers').select('*').order('created_at',{ascending:false}).limit(50),
    supabase.from('inventory_closings').select('*').order('created_at',{ascending:false}).limit(30)
  ]); [ingredients,categories,recipes,suppliers,purchases,movements,wastage,transfers,closings].forEach(x=>fail(x.error));
  return {ingredients:ingredients.data||[],categories:categories.data||[],recipes:recipes.data||[],suppliers:suppliers.data||[],purchases:purchases.data||[],movements:movements.data||[],wastage:wastage.data||[],transfers:transfers.data||[],closings:closings.data||[]}
}
export async function addIngredient(row){const r=await supabase.from('inventory_ingredients').insert(row).select().single();fail(r.error);return r.data}
export async function updateIngredient(id,row){const payload={name:row.name,unit:row.unit,category_id:row.category_id||null,min_stock:Number(row.min_stock||0),avg_cost:Number(row.avg_cost||0),active:row.active!==false};const r=await supabase.from('inventory_ingredients').update(payload).eq('id',id).select().single();fail(r.error);return r.data}
export async function addSupplier(row){const r=await supabase.from('suppliers').insert({name:row.name,phone:row.phone||null,email:row.email||null,address:row.address||null,opening_balance:Number(row.opening_balance||0),active:row.active!==false}).select().single();fail(r.error);return r.data}
export async function updateSupplier(id,row){const r=await supabase.from('suppliers').update({name:row.name,phone:row.phone||null,email:row.email||null,address:row.address||null,opening_balance:Number(row.opening_balance||0),active:row.active!==false}).eq('id',id).select().single();fail(r.error);return r.data}
export async function receivePurchase(payload){const r=await supabase.rpc('nexa_receive_purchase',{p_supplier_id:payload.supplier_id||null,p_reference:payload.reference||null,p_items:payload.items});fail(r.error);return r.data}
export async function recordWastage(ingredientId,qty,reason){const r=await supabase.rpc('nexa_record_wastage',{p_ingredient_id:ingredientId,p_qty:Number(qty),p_reason:reason||null});fail(r.error);return r.data}
export async function createTransfer(ingredientId,qty,toBranchId,notes){const r=await supabase.rpc('nexa_create_stock_transfer',{p_ingredient_id:ingredientId,p_qty:Number(qty),p_to_branch_id:toBranchId,p_notes:notes||null});fail(r.error);return r.data}
export async function saveRecipe(productId,name,yieldQty,items){const r=await supabase.rpc('nexa_save_recipe',{p_product_id:productId,p_name:name,p_yield_qty:Number(yieldQty||1),p_items:items});fail(r.error);return r.data}
export async function loadReconciliation(){const r=await supabase.rpc('nexa_inventory_reconciliation',{});fail(r.error);return r.data||[]}
export async function saveClosing(items,notes=''){const r=await supabase.rpc('nexa_save_inventory_closing',{p_items:items,p_notes:notes});fail(r.error);return r.data}
export function subscribeInventory(refresh){return supabase.channel('nexa-inventory-live').on('postgres_changes',{event:'*',schema:'public',table:'inventory_ingredients'},refresh).on('postgres_changes',{event:'*',schema:'public',table:'inventory_movements'},refresh).subscribe()}
