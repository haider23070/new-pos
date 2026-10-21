import React, { useMemo, useState } from 'react'
import { Ban, Check, Eye, Pencil, Printer, Search, WalletCards } from 'lucide-react'
import { Modal } from '../../components/ui'
import './CarServiceOrdersPage.css'

const money = v => Number(v || 0).toLocaleString('en-PK', { maximumFractionDigits: 2 })
const dateOnly = v => {
  if (!v) return '—'
  const d = new Date(v)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleDateString('en-GB', { day:'2-digit', month:'short' })
}
const timeOnly = v => {
  if (!v) return '—'
  const d = new Date(v)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleTimeString('en-US', { hour:'2-digit', minute:'2-digit' })
}

export default function CarServiceOrdersPage({
  orders = [],
  onCancel,
  onDeliver,
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
        const t = String(o.order_type || '').toLowerCase().replace(/[-_\s]/g,'')
        return t === 'carservice' || t === 'car'
      })
      .filter(o => !['cancelled','draft'].includes(String(o.status || '').toLowerCase()))
      .filter(o => !q || [
        o.invoice_no, o.order_no, o.unique_id, o.created_by_name, o.user_name,
        o.waiter_name, o.waiter?.name, o.customer_name, o.customers?.name,
        o.status, o.remarks, o.notes, o.token, o.token_no,
        o.car_no, o.car_number, o.vehicle_no, o.vehicle_number
      ].filter(Boolean).join(' ').toLowerCase().includes(q))
      .sort((a,b) => new Date(b.created_at || 0) - new Date(a.created_at || 0))
  }, [orders, search])

  const total = rows.reduce((s,o) => s + Number(o.grand_total ?? o.total ?? 0), 0)

  return (
    <div className="car-page">
      <section className="car-card">
        <header className="car-header">
          <h3>Car Service <span>{rows.length}</span></h3>
        </header>

        <div className="car-body">
          <div className="car-tools">
            <div className="car-search">
              <Search size={14}/>
              <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search"/>
            </div>
          </div>

          <div className="car-table-wrap">
            <table className="car-table">
              <tfoot>
                <tr>
                  <th colSpan="10" className="car-total-label">Total of all pages</th>
                  <th className="car-num">{money(total)}</th>
                  <th colSpan="5"/>
                </tr>
              </tfoot>

              <thead>
                <tr>
                  <th>Cancel</th>
                  <th>Invoice No</th>
                  <th>Unique Id</th>
                  <th>Date</th>
                  <th>Time</th>
                  <th>Due | R. Time</th>
                  <th>User</th>
                  <th>Waiter</th>
                  <th>Customer</th>
                  <th>Order Status</th>
                  <th>Amount</th>
                  <th>Bill Printed</th>
                  <th>Remarks</th>
                  <th>Token No.</th>
                  <th>Car No</th>
                  <th>Action</th>
                </tr>
                <tr className="car-filters">
                  <th/>
                  {['Invoice No','Unique Id','','','','User','Waiter','Customer','Order Status','','','Remarks','Token No.','Car No',''].map((p,i)=>
                    <th key={i}>{p && <input value={search} onChange={e=>setSearch(e.target.value)} placeholder={p}/>}</th>
                  )}
                </tr>
              </thead>

              <tbody>
                {!rows.length ? (
                  <tr><td colSpan="16" className="car-empty">No Record Found</td></tr>
                ) : rows.map(o => (
                  <tr key={o.id}>
                    <td>
                      {onCancel && (
                        <button className="car-round danger" title="Cancel Order" onClick={()=>onCancel(o)}>
                          <Ban size={14}/>
                        </button>
                      )}
                    </td>
                    <td>{o.invoice_no || o.order_no || '—'}</td>
                    <td><b>{o.unique_id || String(o.id || '').slice(0,8)}</b></td>
                    <td>{dateOnly(o.created_at)}</td>
                    <td>{timeOnly(o.created_at)}</td>
                    <td>{o.due_time || o.running_time || '—'}</td>
                    <td>{o.created_by_name || o.user_name || '—'}</td>
                    <td>{o.waiter_name || o.waiter?.name || '—'}</td>
                    <td>{o.customers?.name || o.customer_name || 'Walk-in'}</td>
                    <td><span className={`car-status ${String(o.status || '').toLowerCase()}`}>{o.status || 'Processing'}</span></td>
                    <td className="car-num"><b>{money(o.grand_total ?? o.total)}</b></td>
                    <td>{o.bill_printed ? 'Yes' : 'No'}</td>
                    <td className="car-remarks">{o.remarks || o.notes || ''}</td>
                    <td><b>{o.token || o.token_no || '—'}</b></td>
                    <td className="car-number">{o.car_no || o.car_number || o.vehicle_no || o.vehicle_number || '—'}</td>
                    <td>
                      <div className="car-actions">
                        {onDeliver && <button className="deliver" title="Deliver Order" onClick={()=>onDeliver(o)}><Check size={14}/></button>}
                        <button className="detail" title="Items Detail" onClick={()=>{setSelected(o);onView?.(o)}}><Eye size={14}/></button>
                        {onEdit && <button title="Update Order" onClick={()=>onEdit(o)}><Pencil size={14}/></button>}
                        {onPrint && <button title="Print Invoice" onClick={()=>onPrint(o)}><Printer size={14}/></button>}
                        {onPayment && <button className="payment" title="Make Payment" onClick={()=>onPayment(o)}><WalletCards size={14}/></button>}
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <footer className="car-footer">
            <span>{rows.length ? `1-${rows.length} / ${rows.length}` : '0-0 / 0'}</span>
            <div><button disabled>«</button><button className="active">1</button><button disabled>»</button></div>
          </footer>
        </div>
      </section>

      {selected && (
        <Modal
          title="Items Detail"
          subtitle={`Car Service • ${selected.token || selected.token_no || selected.invoice_no || ''}`}
          onClose={()=>setSelected(null)}
          footer={<button className="nxSecondary" onClick={()=>setSelected(null)}>Close</button>}
        >
          <div className="car-detail">
            <div><span>Car No</span><b>{selected.car_no || selected.car_number || selected.vehicle_no || selected.vehicle_number || '—'}</b></div>
            <div><span>Token</span><b>{selected.token || selected.token_no || '—'}</b></div>
            <div><span>Customer</span><b>{selected.customers?.name || selected.customer_name || 'Walk-in'}</b></div>
            <div><span>Waiter</span><b>{selected.waiter_name || selected.waiter?.name || '—'}</b></div>
            <div><span>Status</span><b>{selected.status || 'Processing'}</b></div>
            <div><span>Amount</span><b>Rs {money(selected.grand_total ?? selected.total)}</b></div>
          </div>

          <div className="car-items">
            {(selected.order_items || []).length
              ? selected.order_items.map(i => (
                  <div key={i.id || `${i.name}-${i.qty}`}>
                    <span>{i.qty || 1} × {i.name || 'Item'}</span>
                    <b>Rs {money(Number(i.qty || 0) * Number(i.unit_price || 0))}</b>
                  </div>
                ))
              : <div>No item details loaded for this order.</div>}
          </div>
        </Modal>
      )}
    </div>
  )
}
