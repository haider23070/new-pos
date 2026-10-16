import React,{useEffect,useState} from 'react'
import{CheckCircle2,AlertTriangle,X}from'lucide-react'
export default function AlertCenter(){
 const[items,setItems]=useState([]);
 useEffect(()=>{const onNotify=(event)=>{const text=String(event.detail?.text??'');const type=event.detail?.type||'error';const id=Date.now()+Math.random();setItems(v=>[...v.slice(-3),{id,text,type}]);setTimeout(()=>setItems(v=>v.filter(x=>x.id!==id)),4200)};window.addEventListener('nexa:notify',onNotify);return()=>window.removeEventListener('nexa:notify',onNotify)},[]);
 return <div className="nexaToasts" aria-live="polite">{items.map(x=><div key={x.id} className={'nexaToast '+x.type}><span className="toastIcon">{x.type==='success'?<CheckCircle2/>:<AlertTriangle/>}</span><div><b>{x.type==='success'?'Completed':'Action needs attention'}</b><p>{x.text}</p></div><button aria-label="Dismiss notification" onClick={()=>setItems(v=>v.filter(i=>i.id!==x.id))}><X/></button></div>)}</div>
}
