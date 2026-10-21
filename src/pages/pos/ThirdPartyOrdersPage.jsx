import React, { useMemo, useState } from 'react'
import { Ban, Eye, LockKeyhole, Pencil, Printer, Search, WalletCards } from 'lucide-react'
import { Modal } from '../../components/ui'
import './ThirdPartyOrdersPage.css'

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

export default function ThirdPartyOrdersPage({
  orders = [],
  branchName = '',
  onCancel,
  onDueOrder,
  onView,
  onEdit,
  onPrint,
  onPayment,
  onBulkPayment
}) {
  const [search, setSearch] = useState('')
  const [selected, setSelected] = useState(null)
  const [checked, setChecked] = useState([])

  const rows = useMemo(() => {
    const q = search.trim().toLowerCase()
    return orders
      .filter(o => {
        const type = String(o.order_type || '').toLowerCase().replace(/[-_\s]/g,'')
        return type === 'thirdparty' || type === 'thirdpartyorder'
      })
      .filter(o => !['cancelled','draft'].includes(String(o.status || '').toLowerCase()))
      .filter(o => !q || [
        o.branch_name, branchName, o.token, o.token_no, o.invoice_no, o.order_no,
        o.unique_id, o.created_by_name, o.user_name, o.company, o.company_name,
        o.third_party_name, o.reference, o.reference_no, o.waiter_name,
        o.customer_name, o.customers?.name, o.status, o.remarks, o.notes
      ].filter(Boolean).join(' ').toLowerCase().includes(q))
      .sort((a,b) => new Date(b.created_at || 0) - new Date(a.created_at || 0))
  }, [orders, search, branchName])

  const total = rows.reduce((s,o)=>s+Number(o.grand_total ?? o.total ?? 0),0)
  const selectAll = () => setChecked(rows.map(o=>o.id))
  const toggle = id => setChecked(x => x.includes(id) ? x.filter(v=>v!==id) : [...x,id])

  return (
    <div className="tp-page">
      <section className="tp-card">
        <header className="tp-header">
          <h3>Third-Party <span>{rows.length}</span></h3>
        </header>

        <div className="tp-body">
          <div className="tp-tools">
            <div className="tp-length"><span>Show</span><select defaultValue="all"><option>10</option><option>25</option><option>50</option><option>100</option><option>1000</option><option value="all">All</option></select></div>
            <div className="tp-tools-right">
              <div className="tp-search"><Search size={14}/><input value={search} onChange={e=>setSearch(e.target.value)} placeholder="Search"/></div>
              {onBulkPayment && <button className="tp-primary" onClick={()=>onBulkPayment(checked)}>Bulk Payment</button>}
              <button className="tp-primary" onClick={selectAll}>Select All</button>
            </div>
          </div>

          <div className="tp-table-wrap">
            <table className="tp-table">
              <tfoot>
                <tr><th colSpan="14" className="tp-total-label">Total of all pages</th><th className="tp-num">{money(total)}</th><th colSpan="2"/></tr>
              </tfoot>
              <thead>
                <tr>
                  <th>Cancel</th><th>Branch</th><th>Token No.</th><th>Invoice No</th><th>Unique Id</th>
                  <th>Date</th><th>Time</th><th>Due | R. Time</th><th>User</th><th>Company</th>
                  <th>Reference No</th><th>Waiter</th><th>Customer</th><th>Order Status</th>
                  <th>Amount</th><th>Remarks</th><th>Action</th>
                </tr>
                <tr className="tp-filters">
                  <th/>
                  {['Branch','Token No.','Invoice No','Unique Id','','','','User','Company','Reference No','Waiter','Customer','Order Status','','Remarks',''].map((p,i)=>
                    <th key={i}>{p && <input value={search} onChange={e=>setSearch(e.target.value)} placeholder={p}/>}</th>
                  )}
                </tr>
              </thead>
              <tbody>
                {!rows.length ? <tr><td colSpan="17" className="tp-empty">No Record Found</td></tr> :
                  rows.map(o=>(
                    <tr key={o.id}>
                      <td>
                        <div className="tp-cancel">
                          {onCancel && <button className="danger" title="Cancel Order" onClick={()=>onCancel(o)}><Ban size={14}/></button>}
                          {onDueOrder && <button className="due" title="Due Order" onClick={()=>onDueOrder(o)}><LockKeyhole size={14}/></button>}
                        </div>
                      </td>
                      <td>{o.branch_name || branchName || '—'}</td>
                      <td><b>{o.token || o.token_no || '—'}</b></td>
                      <td>{o.invoice_no || o.order_no || '—'}</td>
                      <td><b>{o.unique_id || String(o.id||'').slice(0,8)}</b></td>
                      <td>{dateOnly(o.created_at)}</td>
                      <td>{timeOnly(o.created_at)}</td>
                      <td>{o.due_time || o.running_time || '—'}</td>
                      <td>{o.created_by_name || o.user_name || '—'}</td>
                      <td>{o.company || o.company_name || o.third_party_name || '—'}</td>
                      <td>{o.reference_no || o.reference || '—'}</td>
                      <td>{o.waiter_name || o.waiter?.name || '—'}</td>
                      <td>{o.customers?.name || o.customer_name || 'Walk-in'}</td>
                      <td><span className={`tp-status ${String(o.status||'').toLowerCase()}`}>{o.status || 'Processing'}</span></td>
                      <td className="tp-num"><b>{money(o.grand_total ?? o.total)}</b></td>
                      <td className="tp-remarks">{o.remarks || o.notes || ''}</td>
                      <td>
                        <div className="tp-actions">
                          <button className="detail" title="Items Detail" onClick={()=>{setSelected(o);onView?.(o)}}><Eye size={14}/></button>
                          {onEdit && <button title="Update Order" onClick={()=>onEdit(o)}><Pencil size={14}/></button>}
                          {onPrint && <button title="Print Invoice" onClick={()=>onPrint(o)}><Printer size={14}/></button>}
                          {onPayment && <button className="payment" title="Make Payment" onClick={()=>onPayment(o)}><WalletCards size={14}/></button>}
                          <label className="tp-check"><input type="checkbox" checked={checked.includes(o.id)} onChange={()=>toggle(o.id)}/></label>
                        </div>
                      </td>
                    </tr>
                  ))
                }
              </tbody>
            </table>
          </div>

          <footer className="tp-footer">
            <span>{rows.length ? `1-${rows.length} / ${rows.length}` : '0-0 / 0'}</span>
            <div><button disabled>«</button><button className="active">1</button><button disabled>»</button></div>
          </footer>
        </div>
      </section>

      {selected && (
        <Modal title="Items Detail" subtitle={`Third-Party • ${selected.token || selected.token_no || selected.invoice_no || ''}`}
          onClose={()=>setSelected(null)}
          footer={<button className="nxSecondary" onClick={()=>setSelected(null)}>Close</button>}>
          <div className="tp-detail">
            <div><span>Company</span><b>{selected.company || selected.company_name || selected.third_party_name || '—'}</b></div>
            <div><span>Reference No</span><b>{selected.reference_no || selected.reference || '—'}</b></div>
            <div><span>Customer</span><b>{selected.customers?.name || selected.customer_name || 'Walk-in'}</b></div>
            <div><span>Status</span><b>{selected.status || 'Processing'}</b></div>
            <div><span>Token</span><b>{selected.token || selected.token_no || '—'}</b></div>
            <div><span>Amount</span><b>Rs {money(selected.grand_total ?? selected.total)}</b></div>
          </div>
          <div className="tp-items">
            {(selected.order_items || []).length
              ? selected.order_items.map(i=><div key={i.id || `${i.name}-${i.qty}`}><span>{i.qty||1} × {i.name||'Item'}</span><b>Rs {money(Number(i.qty||0)*Number(i.unit_price||0))}</b></div>)
              : <div>No item details loaded for this order.</div>}
          </div>
        </Modal>
      )}
    </div>
  )
}
