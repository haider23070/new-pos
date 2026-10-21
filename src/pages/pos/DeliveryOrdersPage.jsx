import React, { useMemo, useState } from 'react'
import { Ban, Eye, LockKeyhole, Pencil, Printer, Search, WalletCards } from 'lucide-react'
import { Modal } from '../../components/ui'
import './DeliveryOrdersPage.css'

const money = v => Number(v || 0).toLocaleString('en-PK', { maximumFractionDigits: 2 })
const dateOnly = v => {
  if (!v) return '—'
  const x = new Date(v)
  return Number.isNaN(x.getTime()) ? '—' : x.toLocaleDateString('en-GB', { day:'2-digit', month:'short' })
}
const timeOnly = v => {
  if (!v) return '—'
  const x = new Date(v)
  return Number.isNaN(x.getTime()) ? '—' : x.toLocaleTimeString('en-US', { hour:'2-digit', minute:'2-digit' })
}

export default function DeliveryOrdersPage({
  orders = [],
  branchName = '',
  onCancel,
  onDueOrder,
  onView,
  onEdit,
  onPrint,
  onPayment,
  onBulkPayment,
  onRiderHandins,
  onRiderRuns,
  onRidersNow
}) {
  const [search, setSearch] = useState('')
  const [selected, setSelected] = useState(null)
  const [checked, setChecked] = useState([])
  const [riderMenu, setRiderMenu] = useState(false)

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase()
    return orders
      .filter(o => {
        const type = String(o.order_type || '').toLowerCase().replace(/[-_\s]/g, '')
        return type === 'delivery'
      })
      .filter(o => !['cancelled','draft'].includes(String(o.status || '').toLowerCase()))
      .filter(o => !q || [
        o.branch_name, branchName, o.token, o.token_no, o.invoice_no, o.order_no,
        o.unique_id, o.created_by_name, o.user_name, o.rider_name, o.rider?.name,
        o.customer_name, o.customers?.name, o.customer_phone,
        o.delivery_address, o.address, o.status, o.delivery_status, o.remarks, o.notes
      ].filter(Boolean).join(' ').toLowerCase().includes(q))
      .sort((a,b) => new Date(b.created_at || 0) - new Date(a.created_at || 0))
  }, [orders, search, branchName])

  const total = rows.reduce((s,o) => s + Number(o.grand_total ?? o.total ?? 0), 0)

  const toggle = id => setChecked(current =>
    current.includes(id) ? current.filter(x => x !== id) : [...current, id]
  )

  const selectAll = () => setChecked(rows.map(o => o.id))

  return (
    <div className="dlv-page">
      <section className="dlv-card">
        <header className="dlv-header">
          <h3>Delivery <span>{rows.length}</span></h3>
        </header>

        <div className="dlv-body">
          <div className="dlv-tools">
            <div className="dlv-search">
              <Search size={14}/>
              <input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search"/>
            </div>

            {onBulkPayment && (
              <button className="dlv-primary" onClick={() => onBulkPayment(checked)}>Bulk Payment</button>
            )}

            <button className="dlv-primary" onClick={selectAll}>Select All</button>

            {(onRiderHandins || onRiderRuns || onRidersNow) && (
              <div className="dlv-rider-menu">
                <button className="dlv-outline" onClick={()=>setRiderMenu(v=>!v)}>Rider App Menu ▾</button>
                {riderMenu && (
                  <div className="dlv-menu">
                    {onRiderHandins && <button onClick={()=>{setRiderMenu(false);onRiderHandins()}}>Rider Handins</button>}
                    {onRiderRuns && <button onClick={()=>{setRiderMenu(false);onRiderRuns()}}>Rider Runs</button>}
                    {onRidersNow && <button onClick={()=>{setRiderMenu(false);onRidersNow()}}>Riders Now</button>}
                  </div>
                )}
              </div>
            )}
          </div>

          <div className="dlv-table-wrap">
            <table className="dlv-table">
              <tfoot>
                <tr>
                  <th colSpan="13" className="dlv-total-label">Total of all pages</th>
                  <th className="dlv-num">{money(total)}</th>
                  <th colSpan="2"/>
                </tr>
              </tfoot>

              <thead>
                <tr>
                  <th>Cancel</th>
                  <th>Branch</th>
                  <th>Token#</th>
                  <th>INV#</th>
                  <th>Unique Id</th>
                  <th>Date</th>
                  <th>Time</th>
                  <th>Due | R. Time</th>
                  <th>User</th>
                  <th>Rider</th>
                  <th>Customer</th>
                  <th>Address</th>
                  <th>Order Status</th>
                  <th>Amount</th>
                  <th>Remarks</th>
                  <th>Action</th>
                </tr>
                <tr className="dlv-filter-row">
                  <th/>
                  {['Branch','Token#','INV#','Unique Id','','','','User','Rider','Customer','Address','','','Remarks',''].map((p,i) =>
                    <th key={i}>{p && <input value={search} onChange={e=>setSearch(e.target.value)} placeholder={p}/>}</th>
                  )}
                </tr>
              </thead>

              <tbody>
                {!rows.length ? (
                  <tr><td colSpan="16" className="dlv-empty">No Delivery orders found</td></tr>
                ) : rows.map(order => (
                  <tr key={order.id} className={order.rider_id ? 'dlv-rider-assigned' : ''}>
                    <td>
                      <div className="dlv-cancel">
                        {onCancel && <button className="danger" title="Cancel Order" onClick={()=>onCancel(order)}><Ban size={14}/></button>}
                        {onDueOrder && <button className="due" title="Due Order" onClick={()=>onDueOrder(order)}><LockKeyhole size={14}/></button>}
                      </div>
                    </td>
                    <td>{order.branch_name || branchName || '—'}</td>
                    <td><b>{order.token || order.token_no || '—'}</b></td>
                    <td>{order.invoice_no || order.order_no || '—'}</td>
                    <td><b>{order.unique_id || String(order.id || '').slice(0,8)}</b></td>
                    <td>{dateOnly(order.created_at)}</td>
                    <td>{timeOnly(order.created_at)}</td>
                    <td>{order.due_time || order.running_time || '—'}</td>
                    <td>{order.created_by_name || order.user_name || '—'}</td>
                    <td>
                      <span className={order.rider_id ? 'dlv-rider assigned' : 'dlv-rider'}>
                        {order.rider_name || order.rider?.name || 'Unassigned'}
                      </span>
                    </td>
                    <td>
                      <b>{order.customers?.name || order.customer_name || 'Walk-in'}</b>
                      {(order.customers?.phone || order.customer_phone) &&
                        <small>{order.customers?.phone || order.customer_phone}</small>}
                    </td>
                    <td className="dlv-address">{order.delivery_address || order.address || '—'}</td>
                    <td>
                      <span className={`dlv-status ${String(order.delivery_status || order.status || '').toLowerCase().replace(/\s/g,'-')}`}>
                        {order.delivery_status || order.status || 'Processing'}
                      </span>
                    </td>
                    <td className="dlv-num"><b>{money(order.grand_total ?? order.total)}</b></td>
                    <td className="dlv-remarks">{order.remarks || order.notes || ''}</td>
                    <td>
                      <div className="dlv-actions">
                        <button className="detail" title="Items Detail" onClick={()=>{setSelected(order);onView?.(order)}}><Eye size={14}/></button>
                        {onEdit && <button title="Update Order" onClick={()=>onEdit(order)}><Pencil size={14}/></button>}
                        {onPrint && <button title="Print Invoice" onClick={()=>onPrint(order)}><Printer size={14}/></button>}
                        {onPayment && <button className="payment" title="Make Payment" onClick={()=>onPayment(order)}><WalletCards size={14}/></button>}
                        <label className="dlv-check" title="Select order">
                          <input type="checkbox" checked={checked.includes(order.id)} onChange={()=>toggle(order.id)}/>
                        </label>
                      </div>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>

          <footer className="dlv-footer">
            <span>{rows.length ? `1-${rows.length} / ${rows.length}` : '0 / 0'}</span>
            <div><button disabled>«</button><button className="active">1</button><button disabled>»</button></div>
          </footer>
        </div>
      </section>

      {selected && (
        <Modal
          title="Items Detail"
          subtitle={`Delivery • ${selected.token || selected.token_no || selected.invoice_no || ''}`}
          onClose={()=>setSelected(null)}
          footer={<button className="nxSecondary" onClick={()=>setSelected(null)}>Close</button>}
        >
          <div className="dlv-detail">
            <div><span>Customer</span><b>{selected.customers?.name || selected.customer_name || 'Walk-in'}</b></div>
            <div><span>Rider</span><b>{selected.rider_name || selected.rider?.name || 'Unassigned'}</b></div>
            <div className="wide"><span>Address</span><b>{selected.delivery_address || selected.address || '—'}</b></div>
            <div><span>Status</span><b>{selected.delivery_status || selected.status || 'Processing'}</b></div>
            <div><span>Amount</span><b>Rs {money(selected.grand_total ?? selected.total)}</b></div>
          </div>

          <div className="dlv-items">
            {(selected.order_items || []).length
              ? selected.order_items.map(item => (
                <div key={item.id || `${item.name}-${item.qty}`}>
                  <span>{item.qty || 1} × {item.name || 'Item'}</span>
                  <b>Rs {money(Number(item.qty || 0) * Number(item.unit_price || 0))}</b>
                </div>
              ))
              : <div>No item details loaded for this order.</div>}
          </div>
        </Modal>
      )}
    </div>
  )
}
