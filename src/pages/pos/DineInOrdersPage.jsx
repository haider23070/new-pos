import React, { useMemo, useState } from 'react'
import { Ban, Eye, History, LockKeyhole, Pencil, Printer, Search, WalletCards } from 'lucide-react'
import { Modal } from '../../components/ui'
import './DineInOrdersPage.css'

const money = v => Number(v || 0).toLocaleString('en-PK', { maximumFractionDigits: 2 })
const d = v => v ? new Date(v).toLocaleDateString('en-GB', { day:'2-digit', month:'short' }) : '—'
const t = v => v ? new Date(v).toLocaleTimeString('en-US', { hour:'2-digit', minute:'2-digit' }) : '—'

export default function DineInOrdersPage({
  orders = [],
  onCancel,
  onDiscard,
  onCustomerHistory,
  onDueOrder,
  onView,
  onEdit,
  onPrint,
  onPayment
}) {
  const [search, setSearch] = useState('')
  const [selected, setSelected] = useState(null)

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase()
    return orders
      .filter(o => {
        const type = String(o.order_type || '').toLowerCase().replace(/[-_\s]/g,'')
        return type === 'dinein' || type === 'dine'
      })
      .filter(o => !['cancelled','draft'].includes(String(o.status || '').toLowerCase()))
      .filter(o => !q || [
        o.invoice_no,o.order_no,o.unique_id,o.created_by_name,o.user_name,
        o.waiter_name,o.customer_name,o.customers?.name,o.status,o.remarks,
        o.notes,o.token,o.token_no,o.table_name,o.tables?.name
      ].filter(Boolean).join(' ').toLowerCase().includes(q))
      .sort((a,b) => new Date(b.created_at||0)-new Date(a.created_at||0))
  }, [orders, search])

  const total = rows.reduce((s,o)=>s+Number(o.grand_total ?? o.total ?? 0),0)

  return (
    <div className="di-page">
      <section className="di-card">
        <header className="di-header">
          <h3>Dine-In <span>{rows.length}</span></h3>
        </header>

        <div className="di-body">
          <div className="di-tools">
            <div className="di-search"><Search size={14}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search"/></div>
          </div>

          <div className="di-scroll">
            <table className="di-table">
              <tfoot>
                <tr>
                  <th colSpan="10" className="di-total-label">Total of all pages</th>
                  <th className="di-num">{money(total)}</th>
                  <th colSpan="5"/>
                </tr>
              </tfoot>
              <thead>
                <tr>
                  <th>Cancel</th><th>Invoice No</th><th>Unique Id</th><th>Date</th><th>Time</th>
                  <th>Due | R. Time</th><th>User</th><th>Waiter</th><th>Customer</th>
                  <th>Order Status</th><th>Amount</th><th>Bill Printed</th><th>Remarks</th>
                  <th>Token No.</th><th>Table</th><th>Action</th>
                </tr>
                <tr className="di-filters">
                  <th/>
                  {['Invoice No','Unique Id','','','','User','Waiter','Customer','Order Status','','','Remarks','Token No.','Table',''].map((x,i)=>
                    <th key={i}>{x && <input placeholder={x} value={search} onChange={e=>setSearch(e.target.value)}/>}</th>
                  )}
                </tr>
              </thead>
              <tbody>
                {!rows.length ? <tr><td colSpan="16" className="di-empty">No Dine-In orders found</td></tr> :
                  rows.map(o => (
                    <tr key={o.id}>
                      <td>
                        <div className="di-cancel-actions">
                          {onCancel && <button className="red" title="Cancel Order" onClick={()=>onCancel(o)}><Ban size={14}/></button>}
                          {onDiscard && <button className="red" title="Discard Order" onClick={()=>onDiscard(o)}><Ban size={14}/></button>}
                          {onCustomerHistory && <button className="gray" title="Customer Order History" onClick={()=>onCustomerHistory(o)}><History size={14}/></button>}
                          {onDueOrder && <button className="blue-soft" title="Due Order" onClick={()=>onDueOrder(o)}><LockKeyhole size={14}/></button>}
                        </div>
                      </td>
                      <td>{o.invoice_no || o.order_no || '—'}</td>
                      <td><b>{o.unique_id || String(o.id||'').slice(0,8)}</b></td>
                      <td>{d(o.created_at)}</td>
                      <td>{t(o.created_at)}</td>
                      <td>{o.due_time || o.running_time || '—'}</td>
                      <td>{o.created_by_name || o.user_name || '—'}</td>
                      <td>{o.waiter_name || o.waiter?.name || '—'}</td>
                      <td>{o.customers?.name || o.customer_name || 'Walk-in'}</td>
                      <td><span className={`di-status ${String(o.status||'').toLowerCase()}`}>{o.status || 'Processing'}</span></td>
                      <td className="di-num"><b>{money(o.grand_total ?? o.total)}</b></td>
                      <td>{o.bill_printed ? 'Yes' : 'No'}</td>
                      <td className="di-wrap">{o.remarks || o.notes || ''}</td>
                      <td><b>{o.token || o.token_no || '—'}</b></td>
                      <td>{o.tables?.name || o.table_name || '—'}</td>
                      <td>
                        <div className="di-row-actions">
                          <button title="Order Details" onClick={()=>{setSelected(o); onView?.(o)}}><Eye size={14}/></button>
                          {onEdit && <button title="Edit Order" onClick={()=>onEdit(o)}><Pencil size={14}/></button>}
                          {onPrint && <button title="Print Bill" onClick={()=>onPrint(o)}><Printer size={14}/></button>}
                          {onPayment && <button title="Make Payment" onClick={()=>onPayment(o)}><WalletCards size={14}/></button>}
                        </div>
                      </td>
                    </tr>
                  ))
                }
              </tbody>
            </table>
          </div>

          <div className="di-footer">
            <span>{rows.length ? `1-${rows.length} / ${rows.length}` : '0 / 0'}</span>
            <div><button disabled>«</button><button className="active">1</button><button disabled>»</button></div>
          </div>
        </div>
      </section>

      {selected && (
        <Modal title="Order Details" subtitle={`Dine-In • ${selected.invoice_no || selected.unique_id || ''}`} onClose={()=>setSelected(null)}
          footer={<button className="nxSecondary" onClick={()=>setSelected(null)}>Close</button>}>
          <div className="di-detail">
            <div><span>Token</span><b>{selected.token || selected.token_no || '—'}</b></div>
            <div><span>Table</span><b>{selected.tables?.name || selected.table_name || '—'}</b></div>
            <div><span>Waiter</span><b>{selected.waiter_name || selected.waiter?.name || '—'}</b></div>
            <div><span>Customer</span><b>{selected.customers?.name || selected.customer_name || 'Walk-in'}</b></div>
            <div><span>Status</span><b>{selected.status || 'Processing'}</b></div>
            <div><span>Amount</span><b>Rs {money(selected.grand_total ?? selected.total)}</b></div>
          </div>
          <div className="di-items">
            {(selected.order_items || []).map(i=><div key={i.id || `${i.name}-${i.qty}`}><span>{i.qty||1} × {i.name||'Item'}</span><b>Rs {money(Number(i.qty||0)*Number(i.unit_price||0))}</b></div>)}
          </div>
        </Modal>
      )}
    </div>
  )
}
