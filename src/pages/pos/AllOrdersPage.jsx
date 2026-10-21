import React, { useEffect, useMemo, useState } from 'react'
import { CreditCard, Eye, Pencil, Printer, ReceiptText, Search } from 'lucide-react'
import { payOrder, updateOrderDiscount } from './services/posApi'
import { queueReceipt } from './services/settingsApi'
import { notify } from './lib/notify'
import { Modal, StatusBadge } from './components/ui'

const money = n => Number(n || 0).toLocaleString('en-PK', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
const tone = s => {
  s = String(s || '').toLowerCase()
  if (/complete|paid|ready|prepared|deliver/.test(s)) return 'success'
  if (/cancel|reject|fail/.test(s)) return 'danger'
  if (/draft|pending|hold|prepar/.test(s)) return 'warning'
  return 'neutral'
}

// Page 1: Mahir-style All / Processing Orders.
// Pass the already-loaded NEXA orders plus your existing refresh/user/permission objects.
export default function AllOrdersPage({ orders = [], user, refresh, hasPermission = () => false }) {
  const [search, setSearch] = useState('')
  const [status, setStatus] = useState('All')
  const [invoice, setInvoice] = useState('')
  const [uniqueId, setUniqueId] = useState('')
  const [customer, setCustomer] = useState('')
  const [token, setToken] = useState('')
  const [selectedId, setSelectedId] = useState(null)
  const [viewing, setViewing] = useState(null)
  const [discounting, setDiscounting] = useState(null)
  const [paying, setPaying] = useState(null)

  const statuses = useMemo(() => [...new Set(orders.map(o => o.status).filter(Boolean))], [orders])

  const rows = useMemo(() => orders.filter(o => {
    const orderStatus = String(o.status || '')
    if (orderStatus.toLowerCase() === 'cancelled') return false
    if (orderStatus.toLowerCase() === 'draft') return false

    const customerText = `${o.customers?.name || o.customer_name || ''} ${o.customers?.phone || o.customer_phone || ''}`.toLowerCase()
    const allText = `${o.invoice_no || ''} ${o.unique_id || ''} ${o.token || o.token_no || ''} ${customerText}`.toLowerCase()

    return (status === 'All' || orderStatus === status) &&
      allText.includes(search.toLowerCase()) &&
      String(o.invoice_no || '').toLowerCase().includes(invoice.toLowerCase()) &&
      String(o.unique_id || o.id || '').toLowerCase().includes(uniqueId.toLowerCase()) &&
      customerText.includes(customer.toLowerCase()) &&
      String(o.token || o.token_no || '').toLowerCase().includes(token.toLowerCase())
  }), [orders, search, status, invoice, uniqueId, customer, token])

  const selected = rows.find(o => o.id === selectedId) || null
  const total = rows.reduce((sum, o) => sum + Number(o.grand_total || 0), 0)

  const requireOrder = fn => selected ? fn(selected) : notify('Select an order first.')
  const print = async order => {
    try { await queueReceipt(order.id); notify('Receipt sent to printer.', 'success') }
    catch (e) { notify(e.message || 'Unable to print receipt.') }
  }

  useEffect(() => {
    const onKey = e => {
      if (['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement?.tagName) || !selected) return
      if (e.key === 'F8') { e.preventDefault(); print(selected) }
      if (e.key === 'F10' && hasPermission('pos.pay')) { e.preventDefault(); setPaying(selected) }
      if (e.shiftKey && e.key.toLowerCase() === 'v') { e.preventDefault(); setViewing(selected) }
      if (e.shiftKey && e.key.toLowerCase() === 'd' && hasPermission('pos.edit')) { e.preventDefault(); setDiscounting(selected) }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [selected, hasPermission])

  return <div className="mahir-all-orders-page">
    <div className="mahir-order-shortcuts">
      {hasPermission('pos.edit') && <button onClick={() => requireOrder(setDiscounting)}><b>%</b><span>Edit Discount<small>shift+d</small></span></button>}
      <button onClick={() => requireOrder(setViewing)}><ReceiptText/><span>View Bill<small>b b</small></span></button>
      <button onClick={() => requireOrder(setViewing)}><Eye/><span>View Order<small>shift+v</small></span></button>
      {hasPermission('pos.edit') && <button onClick={() => notify('Use the existing NEXA Edit Order modal from CompletePOS for the selected order.')}><Pencil/><span>Edit Order<small>shift+e</small></span></button>}
      <button onClick={() => requireOrder(print)}><Printer/><span>Print Bill<small>f8</small></span></button>
      {hasPermission('pos.pay') && <button onClick={() => requireOrder(setPaying)}><CreditCard/><span>Make Payment<small>f10</small></span></button>}
    </div>

    <div className="mahir-orders-filterbar">
      <div className="mahir-global-search"><Search/><input value={search} onChange={e => setSearch(e.target.value)} placeholder="Search" /></div>
      <select value={status} onChange={e => setStatus(e.target.value)}><option>All</option>{statuses.map(s => <option key={s}>{s}</option>)}</select>
      <span>{rows.length} orders</span>
    </div>

    <div className="mahir-orders-table-wrap">
      <table className="mahir-orders-table">
        <thead>
          <tr><th>Invoice No</th><th>Unique Id</th><th>Date</th><th>Time</th><th>Due | R. Time</th><th>User</th><th>Customer</th><th>Order Status</th><th>Amount</th><th>Remarks</th><th>Token No.</th><th>Action</th></tr>
          <tr className="filters">
            <th><input value={invoice} onChange={e=>setInvoice(e.target.value)} placeholder="Invoice No"/></th>
            <th><input value={uniqueId} onChange={e=>setUniqueId(e.target.value)} placeholder="Unique Id"/></th>
            <th/><th/><th/><th/>
            <th><input value={customer} onChange={e=>setCustomer(e.target.value)} placeholder="Customer"/></th>
            <th><select value={status} onChange={e=>setStatus(e.target.value)}><option>All</option>{statuses.map(s=><option key={s}>{s}</option>)}</select></th>
            <th/><th/>
            <th><input value={token} onChange={e=>setToken(e.target.value)} placeholder="Token No."/></th><th/>
          </tr>
        </thead>
        <tbody>
          {rows.map(o => <tr key={o.id} className={selectedId === o.id ? 'selected' : ''} onClick={() => setSelectedId(o.id)}>
            <td><b>{o.invoice_no || '—'}</b></td><td>{o.unique_id || String(o.id).slice(0,8)}</td>
            <td>{new Date(o.created_at).toLocaleDateString()}</td><td>{new Date(o.created_at).toLocaleTimeString([], {hour:'2-digit', minute:'2-digit'})}</td>
            <td>{o.kitchen_status || '—'}</td><td>{o.created_by ? String(o.created_by).slice(0,8) : '—'}</td>
            <td><b>{o.customers?.name || o.customer_name || 'Walk-in'}</b><small>{o.customers?.phone || o.customer_phone || ''}</small></td>
            <td><StatusBadge tone={tone(o.status)}>{o.status}</StatusBadge></td><td className="amount">Rs {money(o.grand_total)}</td>
            <td>{o.remarks || o.notes || '—'}</td><td><b>{o.token || o.token_no || '—'}</b></td>
            <td><button onClick={e=>{e.stopPropagation();setViewing(o)}}><Eye/></button></td>
          </tr>)}
          {!rows.length && <tr><td colSpan="12" className="empty">No processing orders found.</td></tr>}
        </tbody>
        <tfoot><tr><td colSpan="8">Total</td><td className="amount">Rs {money(total)}</td><td colSpan="3"/></tr></tfoot>
      </table>
    </div>

    {viewing && <Modal title={`Order #${viewing.token || viewing.token_no || viewing.invoice_no || ''}`} onClose={()=>setViewing(null)} footer={<button onClick={()=>print(viewing)}><Printer/> Print Bill</button>}>
      <div className="mahir-order-detail"><p><b>Customer:</b> {viewing.customers?.name || viewing.customer_name || 'Walk-in'}</p><p><b>Status:</b> {viewing.status}</p><p><b>Total:</b> Rs {money(viewing.grand_total)}</p>{(viewing.order_items||[]).map(i=><div key={i.id}>{i.qty} × {i.name}<b>Rs {money(Number(i.qty)*Number(i.unit_price))}</b></div>)}</div>
    </Modal>}

    {discounting && <DiscountModal order={discounting} close={()=>setDiscounting(null)} refresh={refresh}/>} 
    {paying && <PaymentModal order={paying} user={user} close={()=>setPaying(null)} refresh={refresh}/>} 
  </div>
}

function DiscountModal({order, close, refresh}) {
  const [value,setValue]=useState(order.discount||0), [busy,setBusy]=useState(false), [error,setError]=useState('')
  const save=async()=>{try{setBusy(true);await updateOrderDiscount(order.id,value);await refresh();close();notify('Discount updated.','success')}catch(e){setError(e.message)}finally{setBusy(false)}}
  return <Modal title="Edit Discount" onClose={close} footer={<><button onClick={close}>Cancel</button><button onClick={save} disabled={busy}>{busy?'Saving…':'Update Discount'}</button></>}>
    {error&&<p>{error}</p>}<label>Discount Amount<input type="number" min="0" max={order.total} value={value} onChange={e=>setValue(e.target.value)}/></label>
  </Modal>
}

function PaymentModal({order,user,close,refresh}) {
  const [cash,setCash]=useState(order.grand_total||0), [card,setCard]=useState(0), [busy,setBusy]=useState(false), [error,setError]=useState('')
  const due=Number(order.grand_total||0), entered=Number(cash||0)+Number(card||0)
  const save=async()=>{if(Math.abs(entered-due)>.01)return setError(`Payment must equal Rs ${money(due)}.`);try{setBusy(true);await payOrder(order.id,user?.id,[{method:'Cash',amount:Number(cash||0)},{method:'Card',amount:Number(card||0)}]);await refresh();close();notify('Payment received.','success')}catch(e){setError(e.message)}finally{setBusy(false)}}
  return <Modal title="Make Payment" onClose={close} footer={<><button onClick={close}>Cancel</button><button onClick={save} disabled={busy}>Confirm Payment</button></>}>
    {error&&<p>{error}</p>}<label>Cash<input type="number" value={cash} onChange={e=>setCash(e.target.value)}/></label><label>Card<input type="number" value={card} onChange={e=>setCard(e.target.value)}/></label><p><b>Due:</b> Rs {money(due)}</p>
  </Modal>
}
