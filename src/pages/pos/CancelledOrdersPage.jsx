import './CancelledOrdersPage.css'
import React, { useMemo, useState } from 'react'
import { Eye, Printer, Search, XCircle } from 'lucide-react'
import { Modal, StatusBadge } from '../../components/ui'

const money = n => Number(n || 0).toLocaleString('en-PK', {
  minimumFractionDigits: 2,
  maximumFractionDigits: 2
})

const dateTime = value => {
  if (!value) return '—'
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? '—' : d.toLocaleString()
}

const minutesBetween = (start, end) => {
  if (!start || !end) return '—'
  const a = new Date(start).getTime()
  const b = new Date(end).getTime()
  if (!Number.isFinite(a) || !Number.isFinite(b)) return '—'
  return Math.max(0, Math.round((b - a) / 60000))
}

const csvCell = value => `"${String(value ?? '').replaceAll('"', '""')}"`

/**
 * Page 2 — Cancelled Orders
 *
 * This page is intentionally separate from AllOrdersPage.
 * It reproduces the Mahir cancelled-order audit layout using the cancellation
 * information NEXA already stores on each order.
 *
 * Props:
 *   orders       already-loaded NEXA orders
 *   onPrint      optional real NEXA receipt-print handler: async order => {}
 *   branchName   optional current branch display name
 */
export default function CancelledOrdersPage({
  orders = [],
  onPrint,
  branchName = ''
}) {
  const [search, setSearch] = useState('')
  const [orderType, setOrderType] = useState('All')
  const [from, setFrom] = useState('')
  const [to, setTo] = useState('')
  const [selected, setSelected] = useState(null)

  const cancelled = useMemo(() => {
    const q = search.trim().toLowerCase()

    return orders
      .filter(o => String(o.status || '').toLowerCase() === 'cancelled')
      .filter(o => orderType === 'All' || o.order_type === orderType)
      .filter(o => {
        const when = new Date(o.cancelled_at || o.updated_at || o.created_at)
        if (from && when < new Date(`${from}T00:00:00`)) return false
        if (to && when > new Date(`${to}T23:59:59`)) return false
        return true
      })
      .filter(o => {
        if (!q) return true
        const text = [
          o.token, o.token_no, o.order_no, o.invoice_no, o.unique_id, o.id,
          o.customer_name, o.customers?.name, o.customer_phone,
          o.order_type, o.cancel_reason, o.remarks, o.notes
        ].filter(Boolean).join(' ').toLowerCase()
        return text.includes(q)
      })
      .sort((a, b) =>
        new Date(b.cancelled_at || b.updated_at || 0) -
        new Date(a.cancelled_at || a.updated_at || 0)
      )
  }, [orders, search, orderType, from, to])

  const orderTypes = useMemo(
    () => [...new Set(
      orders
        .filter(o => String(o.status || '').toLowerCase() === 'cancelled')
        .map(o => o.order_type)
        .filter(Boolean)
    )],
    [orders]
  )

  const totalLines = cancelled.reduce(
    (sum, o) => sum + (o.order_items || []).reduce((n, i) => n + Number(i.qty || 0), 0),
    0
  )
  const orderTotal = cancelled.reduce((sum, o) => sum + Number(o.grand_total || 0), 0)

  const exportCsv = () => {
    const headers = [
      'Sr.', 'Cancelled At', 'Token No.', 'Customer', 'Order ID', 'Unique Id',
      'Branch', 'Order Type', 'Placed at', 'Kind', 'Items', 'Lines',
      'Order total', 'Voided value', 'Cancelled By', 'Authorised by',
      'Void Type', 'Reason', 'Source', 'Cancelled After Mins'
    ]

    const lines = cancelled.map((o, index) => {
      const items = (o.order_items || []).map(i => `${i.qty || 1}x ${i.name || 'Item'}`).join(' | ')
      const qty = (o.order_items || []).reduce((n, i) => n + Number(i.qty || 0), 0)
      return [
        index + 1,
        dateTime(o.cancelled_at || o.updated_at),
        o.token || o.token_no || '',
        o.customers?.name || o.customer_name || 'Walk-in',
        o.order_no || o.invoice_no || String(o.id || '').slice(0, 8),
        o.unique_id || o.id || '',
        o.branch_name || branchName,
        o.order_type || '',
        dateTime(o.created_at),
        'Order',
        items,
        qty,
        Number(o.grand_total || 0).toFixed(2),
        Number(o.grand_total || 0).toFixed(2),
        o.cancelled_by_name || o.cancelled_by || '',
        o.cancel_authorized_by_name || o.cancel_authorized_by || '',
        'Full Order',
        o.cancel_reason || o.remarks || o.notes || '',
        o.source || 'POS',
        minutesBetween(o.created_at, o.cancelled_at || o.updated_at)
      ].map(csvCell).join(',')
    })

    const blob = new Blob([[headers.map(csvCell).join(','), ...lines].join('\n')], {
      type: 'text/csv;charset=utf-8'
    })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `cancelled-orders-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div className="mahir-cancelled-page">
      <div className="cxl-titlebar">
        <div>
          <h2>Cancelled Orders</h2>
          <p>Cancellation audit and void history</p>
        </div>
        <div className="cxl-title-actions">
          <button className="cxl-btn" onClick={exportCsv}>Export CSV</button>
          <button className="cxl-btn" onClick={() => window.print()}>
            <Printer size={15}/> Print
          </button>
        </div>
      </div>

      <div className="cxl-toolbar">
        <label className="cxl-field">
          <span>From</span>
          <input type="date" value={from} onChange={e => setFrom(e.target.value)}/>
        </label>

        <label className="cxl-field">
          <span>To</span>
          <input type="date" value={to} onChange={e => setTo(e.target.value)}/>
        </label>

        <label className="cxl-field">
          <span>Order Type</span>
          <select value={orderType} onChange={e => setOrderType(e.target.value)}>
            <option>All</option>
            {orderTypes.map(type => <option key={type}>{type}</option>)}
          </select>
        </label>

        <label className="cxl-field cxl-search">
          <span>Search</span>
          <div>
            <Search size={15}/>
            <input
              value={search}
              onChange={e => setSearch(e.target.value)}
              placeholder="Token, customer, order ID, reason..."
            />
          </div>
        </label>

        <button
          className="cxl-clear"
          onClick={() => {
            setFrom('')
            setTo('')
            setOrderType('All')
            setSearch('')
          }}
        >
          Clear
        </button>
      </div>

      <div className="cxl-summary">
        <div><span>Cancelled Orders</span><b>{cancelled.length}</b></div>
        <div><span>Lines</span><b>{totalLines}</b></div>
        <div><span>Order Total</span><b>Rs {money(orderTotal)}</b></div>
        <div><span>Voided Value</span><b>Rs {money(orderTotal)}</b></div>
      </div>

      <div className="cxl-table-wrap">
        <table className="cxl-table">
          <thead>
            <tr>
              <th>Sr.</th>
              <th>Cancelled At</th>
              <th>Token No.</th>
              <th>Customer</th>
              <th>Order ID</th>
              <th>Unique Id</th>
              <th>Branch</th>
              <th>Order Type</th>
              <th>Placed at</th>
              <th>Kind</th>
              <th className="wide">Items</th>
              <th className="num">Lines</th>
              <th className="num">Order total</th>
              <th className="num">Voided value</th>
              <th>Cancelled By</th>
              <th>Authorised by</th>
              <th>Void Type</th>
              <th className="wide">Reason</th>
              <th>Source</th>
              <th>Cancelled After Mins</th>
              <th>Action</th>
            </tr>
          </thead>

          <tbody>
            {cancelled.length === 0 ? (
              <tr>
                <td colSpan="21" className="cxl-empty">
                  <XCircle size={30}/>
                  <b>No cancelled orders found</b>
                  <span>Cancelled orders matching the selected filters will appear here.</span>
                </td>
              </tr>
            ) : cancelled.map((o, index) => {
              const items = o.order_items || []
              const qty = items.reduce((n, i) => n + Number(i.qty || 0), 0)

              return (
                <tr key={o.id}>
                  <td>{index + 1}</td>
                  <td>{dateTime(o.cancelled_at || o.updated_at)}</td>
                  <td><b>{o.token || o.token_no || '—'}</b></td>
                  <td>
                    <b>{o.customers?.name || o.customer_name || 'Walk-in'}</b>
                    {(o.customers?.phone || o.customer_phone) &&
                      <small>{o.customers?.phone || o.customer_phone}</small>}
                  </td>
                  <td>{o.order_no || o.invoice_no || String(o.id || '').slice(0, 8)}</td>
                  <td>{o.unique_id || String(o.id || '').slice(0, 8)}</td>
                  <td>{o.branch_name || branchName || '—'}</td>
                  <td>{o.order_type || '—'}</td>
                  <td>{dateTime(o.created_at)}</td>
                  <td><StatusBadge tone="danger">Order</StatusBadge></td>
                  <td className="wide">
                    {items.length
                      ? items.map(i => `${i.qty || 1}× ${i.name || 'Item'}`).join(', ')
                      : '—'}
                  </td>
                  <td className="num">{qty}</td>
                  <td className="num">Rs {money(o.grand_total)}</td>
                  <td className="num"><b>Rs {money(o.grand_total)}</b></td>
                  <td>{o.cancelled_by_name || (o.cancelled_by ? String(o.cancelled_by).slice(0, 8) : '—')}</td>
                  <td>{o.cancel_authorized_by_name || (o.cancel_authorized_by ? String(o.cancel_authorized_by).slice(0, 8) : '—')}</td>
                  <td>Full Order</td>
                  <td className="wide">{o.cancel_reason || o.remarks || o.notes || '—'}</td>
                  <td>{o.source || 'POS'}</td>
                  <td className="num">{minutesBetween(o.created_at, o.cancelled_at || o.updated_at)}</td>
                  <td>
                    <div className="cxl-actions">
                      <button title="View cancelled order" onClick={() => setSelected(o)}>
                        <Eye size={15}/>
                      </button>
                      {onPrint && (
                        <button title="Print" onClick={() => onPrint(o)}>
                          <Printer size={15}/>
                        </button>
                      )}
                    </div>
                  </td>
                </tr>
              )
            })}
          </tbody>

          {cancelled.length > 0 && (
            <tfoot>
              <tr>
                <td colSpan="11"><b>Total</b></td>
                <td className="num"><b>{totalLines}</b></td>
                <td className="num"><b>Rs {money(orderTotal)}</b></td>
                <td className="num"><b>Rs {money(orderTotal)}</b></td>
                <td colSpan="7"/>
              </tr>
            </tfoot>
          )}
        </table>
      </div>

      <div className="cxl-footer">
        <span>{cancelled.length ? `1-${cancelled.length} / ${cancelled.length}` : '0 / 0'}</span>
      </div>

      {selected && (
        <Modal
          title={`Cancelled Order #${selected.token || selected.token_no || selected.invoice_no || ''}`}
          subtitle={`Cancelled ${dateTime(selected.cancelled_at || selected.updated_at)}`}
          onClose={() => setSelected(null)}
          footer={<button className="nxSecondary" onClick={() => setSelected(null)}>Close</button>}
        >
          <div className="cxl-detail-grid">
            <div><span>Customer</span><b>{selected.customers?.name || selected.customer_name || 'Walk-in'}</b></div>
            <div><span>Order Type</span><b>{selected.order_type || '—'}</b></div>
            <div><span>Order Total</span><b>Rs {money(selected.grand_total)}</b></div>
            <div><span>Cancelled After</span><b>{minutesBetween(selected.created_at, selected.cancelled_at || selected.updated_at)} mins</b></div>
            <div><span>Cancelled By</span><b>{selected.cancelled_by_name || selected.cancelled_by || '—'}</b></div>
            <div><span>Authorised By</span><b>{selected.cancel_authorized_by_name || selected.cancel_authorized_by || '—'}</b></div>
          </div>

          <div className="cxl-reason">
            <span>Cancellation Reason</span>
            <b>{selected.cancel_reason || selected.remarks || selected.notes || 'No reason recorded'}</b>
          </div>

          <div className="cxl-items">
            {(selected.order_items || []).map(item => (
              <div key={item.id || `${item.name}-${item.qty}`}>
                <span>{item.qty || 1} × {item.name || 'Item'}</span>
                <b>Rs {money(Number(item.qty || 0) * Number(item.unit_price || 0))}</b>
              </div>
            ))}
          </div>
        </Modal>
      )}
    </div>
  )
}
