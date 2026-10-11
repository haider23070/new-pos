import {supabase} from '../lib/supabase'
const req=e=>{if(e)throw e}

// Read the complete menu-management snapshot through one authenticated RPC.
// This prevents one failed/RLS-filtered table query from blanking every dropdown.
export async function loadMenuAdmin(_branchId){
 const {data,error}=await supabase.rpc('nexa_menu_admin_snapshot')
 req(error)
 const x=data||{}
 return{
  categories:Array.isArray(x.categories)?x.categories:[],
  items:Array.isArray(x.items)?x.items:[],
  departments:Array.isArray(x.departments)?x.departments:[],
  printers:Array.isArray(x.printers)?x.printers:[]
 }
}
export async function addCategory(_branchId,name){const{data,error}=await supabase.rpc('nexa_create_category',{p_name:name});req(error);return data}
export async function addDepartment(_branchId,name){const{data,error}=await supabase.rpc('nexa_create_kitchen_department',{p_name:name});req(error);return data}
export async function savePrinter(_branchId,{name,printer_name,department_id}){const{data,error}=await supabase.rpc('nexa_save_kitchen_printer',{p_name:name,p_printer_name:printer_name,p_department_id:department_id||null});req(error);return data}
export async function addMenuItem(_branchId,{name,category_id,department_id,variantName,price,image_url}){const{data,error}=await supabase.rpc('nexa_create_menu_item',{p_name:name,p_category_id:category_id||null,p_department_id:department_id||null,p_variant_name:variantName||'Regular',p_price:Number(price),p_image_url:image_url||null});req(error);return data}
export async function toggleMenuItem(id,active){const{data,error}=await supabase.rpc('nexa_toggle_menu_item',{p_item_id:id,p_active:active});req(error);return data}
