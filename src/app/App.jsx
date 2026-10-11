import React,{useEffect} from 'react'
import {useAuth}from'../context/AuthContext'
import Login from '../pages/auth/Login'
import OperationsApp from './OperationsApp'
import PublicSite from '../pages/PublicSite'
import DeliveryMobile from '../pages/DeliveryMobile'
import OrderTakerMobile from '../pages/OrderTakerMobile'
export default function App(){
 const{session,loading,profile}=useAuth();const path=window.location.pathname;const system=path==='/system'||path.startsWith('/system/');
 useEffect(()=>{const t=localStorage.getItem('nexa-theme')||profile?.theme||'dark';document.documentElement.dataset.theme=t==='system'?(matchMedia('(prefers-color-scheme: light)').matches?'light':'dark'):t},[profile?.theme]);
 if(!system)return <PublicSite/>;
 if(loading)return <div className="boot">Loading NEXA…</div>;
 if(!session)return <Login/>;
 if(!profile?.id||profile?.active===false)return <div className="boot">This account does not have active NEXA staff access.</div>;
 if(profile?.role==='Delivery Boy')return <DeliveryMobile/>;if(profile?.role==='Order Taker')return <OrderTakerMobile/>;return <OperationsApp/>
}
