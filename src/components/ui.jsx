import React from 'react'
import {AlertCircle,Inbox,LoaderCircle,RefreshCw,Search,X} from 'lucide-react'

export function PageHeader({eyebrow,title,description,children}){return <div className="nxPageHeader"><div><span className="nxEyebrow">{eyebrow}</span><h1>{title}</h1>{description&&<p>{description}</p>}</div>{children&&<div className="nxHeaderActions">{children}</div>}</div>}
export function SearchBox({value,onChange,placeholder='Search…'}){return <label className="nxSearch"><Search/><input value={value} onChange={e=>onChange(e.target.value)} placeholder={placeholder}/>{value&&<button type="button" aria-label="Clear search" onClick={()=>onChange('')}><X/></button>}</label>}
export function EmptyState({title='Nothing here yet',description='Records will appear here when available.',action}){return <div className="nxEmpty"><span><Inbox/></span><h3>{title}</h3><p>{description}</p>{action}</div>}
export function ErrorState({message='Unable to load this page.',onRetry}){return <div className="nxError"><AlertCircle/><div><b>Something went wrong</b><p>{message}</p></div>{onRetry&&<button className="btn" onClick={onRetry}><RefreshCw/> Retry</button>}</div>}
export function LoadingState({label='Loading…'}){return <div className="nxLoading"><LoaderCircle/><span>{label}</span></div>}
export function StatusBadge({children,tone='neutral'}){return <span className={'nxStatus '+tone}>{children}</span>}
export function Modal({title,subtitle,onClose,children,footer,className=''}){return <div className="overlay" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)onClose?.()}}><section className={'nxModal '+className} role="dialog" aria-modal="true" aria-label={title}><header><div><h2>{title}</h2>{subtitle&&<p>{subtitle}</p>}</div><button className="nxIconBtn" onClick={onClose} aria-label="Close"><X/></button></header><div className="nxModalBody">{children}</div>{footer&&<footer>{footer}</footer>}</section></div>}
