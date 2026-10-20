import React,{useEffect,useMemo,useState} from 'react';
import {Download,Printer,RefreshCw,Search,ChevronLeft} from 'lucide-react';
import {supabase} from '../lib/supabase';
import {useAuth} from '../context/AuthContext';
import './reportsCenter.css';

const GROUPS=[
 {title:'Food Sale',items:['Register Summary / Z-report v1','Register Summary / Z-report v2','Registers','Invoice Wise','Item Wise','Day Wise Item Sale','Variant Wise','Variant Wise Summary','Order Type Wise Variant','Product Wise','Day Wise Product Sale','Order Type Wise Product','Waiter Wise Product','Category Wise','Department Wise','Department Summary','Order Type Wise','Shift Wise Order Type','Waiter Wise','Kitchen & Rider Performance','Rider Check-in/Out History','Rider Status Dashboard','Rider KMs','Rider KMs Monthly']},
 {title:'Food Sale',items:['Date Wise','Cashier Wise','Customer Wise','Customer Wise (Summary)','All Orders','Hourly Sales Trends','Hourly Sales','Hourly Sales Tracking','Hourly Sales Category','Hourly Sales Item','Date Wise Summary','Discounted Orders','Complimentary Orders','Rider Wise Grouping']},
 {title:'Due Orders',items:['Care Of Wise Due','Customer Wise Due','Staff Wise Due','Order Type Wise Due','Customer Wise Summary','Due Order Paid']},
 {title:'Cancelled',items:['Made Food Order','Un Made Food Order','Cancelled Items']},
 {title:'Discounts',items:['Discount Summary','Discounted Orders Detail']},
 {title:'Review Reports',items:['Customer Reviews','Low Rating Reviews']},
 {title:'Menu Costing & Stats',items:['Menu Engineering']},
];
const INV_GROUPS=[
 {title:'Purchase & Inventory',items:['Purchase Summary','Purchase Detail','Supplier Wise Purchase','Ingredient Stock','Low Stock','Inventory Movements','Wastage','Stock Transfers','Stock Reconciliation']},
];
const RAW_GROUPS=[{title:'Raw Material Sale',items:['Recipe Consumption','Ingredient Consumption','Theoretical Usage','Wastage Detail','Inventory Variance']}];
const money=n=>'Rs '+Number(n||0).toLocaleString(undefined,{maximumFractionDigits:2});
const day=v=>String(v||'').slice(0,10); const hour=v=>{try{return new Date(v).getHours().toString().padStart(2,'0')+':00'}catch{return ''}};
const sum=(a,k)=>a.reduce((s,x)=>s+Number(x[k]||0),0);
const group=(rows,key,make)=>Object.values(rows.reduce((a,r)=>{const k=typeof key==='function'?key(r):r[key]||'Unknown';a[k]??=make(k);a[k]._rows=(a[k]._rows||0)+1;return a},{}));

export default function ReportsCenter(){
 const {profile}=useAuth(); const privileged=['Developer','Admin'].includes(profile?.role);
 const [section,setSection]=useState('Food Sale'); const [report,setReport]=useState(null); const [start,setStart]=useState(()=>new Date(new Date().setDate(1)).toISOString().slice(0,10)); const [end,setEnd]=useState(()=>new Date().toISOString().slice(0,10));
 const groups=section==='Food Sale'?GROUPS:section==='Purchase & Inventory'?INV_GROUPS:RAW_GROUPS;
 return <div className="rptShell">
   {!report?<Directory section={section} setSection={setSection} groups={groups} onOpen={x=>{if(x==='Menu Engineering'&&!privileged)return;setReport(x)}} privileged={privileged}/>:<ReportView name={report} start={start} end={end} setStart={setStart} setEnd={setEnd} onBack={()=>setReport(null)} profile={profile}/>} 
 </div>
}
function Directory({section,setSection,groups,onOpen,privileged}){return <div className="rptDirectory">
 <aside><h3>Reports</h3>{['Food Sale','Purchase & Inventory','Raw Material Sale'].map(x=><button key={x} className={section===x?'on':''} onClick={()=>setSection(x)}>{x}<span>→</span></button>)}</aside>
 <main>{groups.map((g,i)=><section key={g.title+i}><h4>{g.title}</h4>{g.items.map(x=><button key={x} disabled={x==='Menu Engineering'&&!privileged} onClick={()=>onOpen(x)}>{x}{x==='Menu Engineering'&&<small> Only Admin/Developer · BETA</small>}</button>)}</section>)}</main>
 </div>}
function ReportView({name,start,end,setStart,setEnd,onBack,profile}){
 const [rows,setRows]=useState([]),[loading,setLoading]=useState(false),[err,setErr]=useState('');
 const load=async()=>{setLoading(true);setErr('');try{setRows(await buildReport(name,start,end,profile))}catch(e){setErr(e.message||String(e));setRows([])}finally{setLoading(false)}};
 useEffect(()=>{load()},[name,start,end]);
 const cols=useMemo(()=>rows.length?Object.keys(rows[0]):[],[rows]);
 const csv=()=>{if(!rows.length)return;const text=[cols.join(','),...rows.map(r=>cols.map(c=>JSON.stringify(r[c]??'')).join(','))].join('\n');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([text],{type:'text/csv'}));a.download=`NEXA-${name.replace(/\W+/g,'-')}-${start}-${end}.csv`;a.click();URL.revokeObjectURL(a.href)};
 return <div className="rptView"><header><div><button className="back" onClick={onBack}><ChevronLeft size={15}/> Reports</button><h2>{name}</h2></div><div className="filters"><input type="date" value={start} onChange={e=>setStart(e.target.value)}/><span>to</span><input type="date" value={end} onChange={e=>setEnd(e.target.value)}/><button onClick={load}><RefreshCw size={14}/>{loading?' Loading':' Refresh'}</button><button onClick={csv}><Download size={14}/> CSV</button><button onClick={()=>window.print()}><Printer size={14}/> Print</button></div></header>{err&&<div className="rptErr">{err}</div>}<div className="rptMeta"><b>{rows.length}</b> rows <span>•</span> {start} — {end}</div><div className="rptTableWrap"><table><thead><tr>{cols.map(c=><th key={c}>{c.replaceAll('_',' ')}</th>)}</tr></thead><tbody>{rows.map((r,i)=><tr key={i}>{cols.map(c=><td key={c}>{format(r[c],c)}</td>)}</tr>)}{!rows.length&&!loading&&<tr><td colSpan={Math.max(1,cols.length)}>No data found for this period.</td></tr>}</tbody></table></div></div>
}
const format=(v,k)=>/amount|sale|total|discount|tax|due|paid|cost|revenue|profit/i.test(k)?money(v):String(v??'—');
async function baseOrders(start,end){const {data,error}=await supabase.from('orders').select('id,branch_id,shift_id,customer_id,table_id,token,invoice_no,order_type,status,kitchen_status,delivery_status,total,discount,tax,grand_total,created_by,created_at,completed_at,cancel_reason').gte('created_at',start+'T00:00:00').lte('created_at',end+'T23:59:59').order('created_at',{ascending:false});if(error)throw error;return data||[]}
async function itemsFor(ids){if(!ids.length)return[];const {data,error}=await supabase.from('order_items').select('id,order_id,item_id,variant_id,name,qty,unit_price,status,notes').in('order_id',ids);if(error)throw error;return data||[]}
async function buildReport(name,start,end,profile){
 const orders=await baseOrders(start,end), ids=orders.map(x=>x.id), completed=orders.filter(x=>!['Cancelled','Draft'].includes(x.status));
 const orderMap=Object.fromEntries(orders.map(x=>[x.id,x]));
 if(name==='All Orders'||name==='Invoice Wise'||name.includes('Register')) return orders.map(o=>({date:day(o.created_at),invoice:o.invoice_no,token:o.token,type:o.order_type,status:o.status,kitchen:o.kitchen_status,total:o.grand_total,discount:o.discount,tax:o.tax}));
 if(name==='Date Wise'||name==='Date Wise Summary'){const m={};completed.forEach(o=>{const k=day(o.created_at);m[k]??={date:k,orders:0,gross_sales:0,discount:0,tax:0,net_sales:0};m[k].orders++;m[k].gross_sales+=Number(o.total||0);m[k].discount+=Number(o.discount||0);m[k].tax+=Number(o.tax||0);m[k].net_sales+=Number(o.grand_total||0)});return Object.values(m)}
 if(name==='Order Type Wise'||name==='Shift Wise Order Type'){const m={};completed.forEach(o=>{const k=o.order_type||'Unknown';m[k]??={order_type:k,orders:0,total:0};m[k].orders++;m[k].total+=Number(o.grand_total||0)});return Object.values(m)}
 if(name==='Discounted Orders'||name==='Discounted Orders Detail') return completed.filter(o=>Number(o.discount)>0).map(o=>({date:day(o.created_at),invoice:o.invoice_no,token:o.token,type:o.order_type,discount:o.discount,total:o.grand_total}));
 if(name.startsWith('Cancelled')||name==='Made Food Order'||name==='Un Made Food Order'){const c=orders.filter(o=>o.status==='Cancelled');if(name==='Cancelled Items'){const its=await itemsFor(c.map(x=>x.id));return its.map(i=>({invoice:orderMap[i.order_id]?.invoice_no,item:i.name,qty:i.qty,price:i.unit_price,status:i.status}))}return c.map(o=>({date:day(o.created_at),invoice:o.invoice_no,token:o.token,type:o.order_type,kitchen:o.kitchen_status,total:o.grand_total,reason:o.cancel_reason}))}
 if(name.includes('Hourly')){const m={};completed.forEach(o=>{const k=hour(o.created_at);m[k]??={hour:k,orders:0,sales:0};m[k].orders++;m[k].sales+=Number(o.grand_total||0)});return Object.values(m).sort((a,b)=>a.hour.localeCompare(b.hour))}
 if(/Item|Product|Variant|Category|Department/.test(name)){const its=await itemsFor(completed.map(x=>x.id));const m={};its.forEach(i=>{const o=orderMap[i.order_id];let k=i.name||'Unknown';if(name.includes('Variant'))k=i.variant_id||'Default';if(name.includes('Order Type'))k=(o?.order_type||'Unknown')+' · '+k;m[k]??={name:k,qty:0,sales:0,orders:new Set()};m[k].qty+=Number(i.qty||0);m[k].sales+=Number(i.qty||0)*Number(i.unit_price||0);m[k].orders.add(i.order_id)});return Object.values(m).map(x=>({name:x.name,orders:x.orders.size,qty:x.qty,sales:x.sales}))}
 if(name==='Cashier Wise'||name==='Waiter Wise'){const m={};completed.forEach(o=>{const k=o.created_by||'Unknown';m[k]??={staff_id:k,orders:0,sales:0};m[k].orders++;m[k].sales+=Number(o.grand_total||0)});return Object.values(m)}
 if(name.includes('Customer Wise')){const m={};completed.forEach(o=>{const k=o.customer_id||'Walk-in';m[k]??={customer_id:k,orders:0,sales:0};m[k].orders++;m[k].sales+=Number(o.grand_total||0)});return Object.values(m)}
 if(name.includes('Due')){const {data:p,error}=await supabase.from('payments').select('order_id,amount,status').in('order_id',ids);if(error)throw error;const paid={};(p||[]).filter(x=>x.status==='Paid').forEach(x=>paid[x.order_id]=(paid[x.order_id]||0)+Number(x.amount||0));return completed.map(o=>({...o,due:Math.max(0,Number(o.grand_total||0)-(paid[o.id]||0)),paid:paid[o.id]||0})).filter(x=>x.due>0).map(o=>({invoice:o.invoice_no,token:o.token,type:o.order_type,total:o.grand_total,paid:o.paid,due:o.due}))}
 if(name==='Rider Check-in/Out History'){const {data,error}=await supabase.from('rider_attendance').select('*').gte('started_at',start+'T00:00:00').lte('started_at',end+'T23:59:59').order('started_at',{ascending:false});if(error)throw error;return data||[]}
 if(name==='Rider Status Dashboard'){const {data,error}=await supabase.from('pos_riders').select('*').order('name');if(error)throw error;return data||[]}
 if(name.includes('Rider')){const {data,error}=await supabase.from('deliveries').select('id,order_id,rider_id,status,assigned_at,handed_over_at,delivered_at').in('order_id',ids);if(error)throw error;const m={};(data||[]).forEach(d=>{const k=d.rider_id||'Unassigned';m[k]??={rider_id:k,orders:0,delivered:0,sales:0};m[k].orders++;if(d.status==='Delivered')m[k].delivered++;m[k].sales+=Number(orderMap[d.order_id]?.grand_total||0)});return Object.values(m)}
 if(name.includes('Purchase')){const {data,error}=await supabase.from('inventory_purchases').select('*').gte('created_at',start+'T00:00:00').lte('created_at',end+'T23:59:59').order('created_at',{ascending:false});if(error)throw error;return data||[]}
 if(name==='Ingredient Stock'||name==='Low Stock'){const {data,error}=await supabase.from('inventory_ingredients').select('name,unit,current_stock,min_stock,avg_cost,active').order('name');if(error)throw error;return name==='Low Stock'?(data||[]).filter(x=>Number(x.current_stock)<=Number(x.min_stock)):data||[]}
 if(name==='Inventory Movements'||name==='Recipe Consumption'||name==='Ingredient Consumption'||name==='Theoretical Usage'){const {data,error}=await supabase.from('inventory_movements').select('*').gte('created_at',start+'T00:00:00').lte('created_at',end+'T23:59:59').order('created_at',{ascending:false});if(error)throw error;return name==='Inventory Movements'?(data||[]):(data||[]).filter(x=>x.movement_type==='CONSUMPTION')}
 if(name.includes('Wastage')){const {data,error}=await supabase.from('inventory_wastage').select('*').gte('created_at',start+'T00:00:00').lte('created_at',end+'T23:59:59').order('created_at',{ascending:false});if(error)throw error;return data||[]}
 if(name==='Stock Transfers'){const {data,error}=await supabase.from('inventory_transfers').select('*').gte('created_at',start+'T00:00:00').lte('created_at',end+'T23:59:59').order('created_at',{ascending:false});if(error)throw error;return data||[]}
 if(name==='Stock Reconciliation'||name==='Inventory Variance'){const {data,error}=await supabase.from('inventory_closing_items').select('*');if(error)throw error;return data||[]}
 if(name==='Menu Engineering'){const its=await itemsFor(completed.map(x=>x.id));const m={};its.forEach(i=>{m[i.name]??={item:i.name,qty:0,revenue:0};m[i.name].qty+=Number(i.qty);m[i.name].revenue+=Number(i.qty)*Number(i.unit_price)});return Object.values(m).sort((a,b)=>b.revenue-a.revenue)}
 if(name==='Discount Summary'){return [{orders:completed.filter(o=>Number(o.discount)>0).length,discount_amount:sum(completed,'discount'),gross_sales:sum(completed,'total'),net_sales:sum(completed,'grand_total')}]}
 if(name==='Complimentary Orders')return [];
 return orders.map(o=>({date:day(o.created_at),invoice:o.invoice_no,token:o.token,type:o.order_type,status:o.status,total:o.grand_total}));
}
