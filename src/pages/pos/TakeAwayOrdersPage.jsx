import React, { useMemo, useState } from 'react'
import {
  Ban, Check, Eye, History, LockKeyhole, Pencil, Printer, Search, WalletCards
} from 'lucide-react'
import { Modal } from '../../components/ui'
import './TakeAwayOrdersPage.css'

const money = value => Number(value || 0).toLocaleString('en-PK', { maximumFractionDigits: 2 })

const dateOnly = value => {
  if (!value) return '—'
  const x = new Date(value)
  return Number.isNaN(x.getTime()) ? '—' : x.toLocaleDateString('en-GB', {
    day: '2-digit',
    month: 'short'
  })
}

const timeOnly = value => {
  if (!value) return '—'
  const x = new Date(value)
  return Number.isNaN(x.getTime()) ? '—' : x.toLocaleTimeString('en-US', {
    hour: '2-digit',
    minute: '2-digit'
  })
}

/**
 * Page 5 — Take Away
 *
 * All action props should be connected to the EXISTING NEXA handlers.
 * No backend calls are invented inside this UI component.
 */
export default function TakeAwayOrdersPage({
  orders = [],
  branchName = '',
  onCancel,
  onDiscard,
  onCustomerHistory,
  onDueOrder,
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
      .filter(order => {
        const type = String(order.order_type || '')
          .toLowerCase()
          .replace(/[-_\s]/g, '')

        return type === 'takeaway' || type === 'takeout' || type === 'take'
      })
      .filter(order => {
        const status = String(order.status || '').toLowerCase()
        return !['cancelled', 'draft'].includes(status)
      })
      .filter(order => {
        if (!q) return true

        return [
          order.branch_name,
          branchName,
          order.token,
          order.token_no,
          order.invoice_no,
          order.order_no,
          order.unique_id,
          order.created_by_name,
          order.user_name,
          order.waiter_name,
          order.waiter?.name,
          order.customer_name,
          order.customers?.name,
          order.status,
          order.remarks,
          order.notes
        ]
          .filter(Boolean)
          .join(' ')
          .toLowerCase()
          .includes(q)
      })
      .sort(
        (a, b) =>
          new Date(b.created_at || 0).getTime() -
          new Date(a.created_at || 0).getTime()
      )
  }, [orders, search, branchName])

  const total = rows.reduce(
    (sum, order) => sum + Number(order.grand_total ?? order.total ?? 0),
    0
  )

  const openDetails = order => {
    setSelected(order)
    onView?.(order)
  }

  return (
    <div className="ta-page">
      <section className="ta-card">
        <header className="ta-header">
          <h3>
            Take-Away
            <span className="ta-count">{rows.length}</span>
          </h3>
        </header>

        <div className="ta-body">
          <div className="ta-tools">
            <div className="ta-search">
              <Search size={14} />
              <input
                type="search"
                value={search}
                onChange={event => setSearch(event.target.value)}
                placeholder="Search"
              />
            </div>
          </div>

          <div className="ta-table-wrap">
            <table className="ta-table">
              <tfoot>
                <tr>
                  <th colSpan="12" className="ta-total-label">
                    Total of all pages
                  </th>
                  <th className="ta-number">{money(total)}</th>
                  <th colSpan="2" />
                </tr>
              </tfoot>

              <thead>
                <tr>
                  <th>Cancel</th>
                  <th>Branch</th>
                  <th>Token No.</th>
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
                  <th>Remarks</th>
                  <th>Action</th>
                </tr>

                <tr className="ta-filter-row">
                  <th />
                  {[
                    'Branch',
                    'Token No.',
                    'Invoice No',
                    'Unique Id',
                    '',
                    '',
                    '',
                    'User',
                    'Waiter',
                    'Customer',
                    'Order Status',
                    '',
                    'Remarks',
                    ''
                  ].map((placeholder, index) => (
                    <th key={index}>
                      {placeholder && (
                        <input
                          value={search}
                          onChange={event => setSearch(event.target.value)}
                          placeholder={placeholder}
                        />
                      )}
                    </th>
                  ))}
                </tr>
              </thead>

              <tbody>
                {!rows.length ? (
                  <tr>
                    <td colSpan="15" className="ta-empty">
                      No Take-Away orders found
                    </td>
                  </tr>
                ) : (
                  rows.map(order => (
                    <tr key={order.id}>
                      <td>
                        <div className="ta-cancel-actions">
                          {onCancel && (
                            <button
                              className="danger-soft"
                              title="Cancel Order"
                              onClick={() => onCancel(order)}
                            >
                              <Ban size={14} />
                            </button>
                          )}

                          {onDiscard && (
                            <button
                              className="danger-soft"
                              title="Discard Order"
                              onClick={() => onDiscard(order)}
                            >
                              <Ban size={14} />
                            </button>
                          )}

                          {onCustomerHistory && (
                            <button
                              className="secondary-soft"
                              title="Customer Order History"
                              onClick={() => onCustomerHistory(order)}
                            >
                              <History size={14} />
                            </button>
                          )}

                          {onDueOrder && (
                            <button
                              className="primary-soft"
                              title="Due Order"
                              onClick={() => onDueOrder(order)}
                            >
                              <LockKeyhole size={14} />
                            </button>
                          )}
                        </div>
                      </td>

                      <td>{order.branch_name || branchName || '—'}</td>
                      <td>
                        <b>{order.token || order.token_no || '—'}</b>
                      </td>
                      <td>{order.invoice_no || order.order_no || '—'}</td>
                      <td>
                        <span className="ta-uid">
                          {order.unique_id || String(order.id || '').slice(0, 8)}
                        </span>
                      </td>
                      <td>{dateOnly(order.created_at)}</td>
                      <td>{timeOnly(order.created_at)}</td>
                      <td>{order.due_time || order.running_time || '—'}</td>
                      <td>{order.created_by_name || order.user_name || '—'}</td>
                      <td>{order.waiter_name || order.waiter?.name || '—'}</td>
                      <td>
                        {order.customers?.name || order.customer_name || 'Walk-in'}
                      </td>
                      <td>
                        <span
                          className={`ta-status ${String(
                            order.status || ''
                          ).toLowerCase()}`}
                        >
                          {order.status || 'Processing'}
                        </span>
                      </td>
                      <td className="ta-number">
                        <b>{money(order.grand_total ?? order.total)}</b>
                      </td>
                      <td className="ta-remarks">
                        {order.remarks || order.notes || ''}
                      </td>
                      <td>
                        <div className="ta-actions">
                          {onDeliver && (
                            <button
                              className="deliver"
                              title="Deliver Order"
                              onClick={() => onDeliver(order)}
                            >
                              <Check size={14} />
                            </button>
                          )}

                          <button
                            className="detail"
                            title="Items Detail"
                            onClick={() => openDetails(order)}
                          >
                            <Eye size={14} />
                          </button>

                          {onEdit && (
                            <button
                              title="Update Order"
                              onClick={() => onEdit(order)}
                            >
                              <Pencil size={14} />
                            </button>
                          )}

                          {onPrint && (
                            <button
                              title="Print Invoice"
                              onClick={() => onPrint(order)}
                            >
                              <Printer size={14} />
                            </button>
                          )}

                          {onPayment && (
                            <button
                              className="payment"
                              title="Make Payment"
                              onClick={() => onPayment(order)}
                            >
                              <WalletCards size={14} />
                            </button>
                          )}
                        </div>
                      </td>
                    </tr>
                  ))
                )}
              </tbody>
            </table>
          </div>

          <footer className="ta-footer">
            <span>
              {rows.length ? `1-${rows.length} / ${rows.length}` : '0 / 0'}
            </span>

            <div>
              <button disabled>«</button>
              <button className="active">1</button>
              <button disabled>»</button>
            </div>
          </footer>
        </div>
      </section>

      {selected && (
        <Modal
          title="Items Detail"
          subtitle={`Take-Away • ${
            selected.token ||
            selected.token_no ||
            selected.invoice_no ||
            selected.unique_id ||
            ''
          }`}
          onClose={() => setSelected(null)}
          footer={
            <button
              className="nxSecondary"
              onClick={() => setSelected(null)}
            >
              Close
            </button>
          }
        >
          <div className="ta-detail-grid">
            <div>
              <span>Branch</span>
              <b>{selected.branch_name || branchName || '—'}</b>
            </div>
            <div>
              <span>Token</span>
              <b>{selected.token || selected.token_no || '—'}</b>
            </div>
            <div>
              <span>Customer</span>
              <b>
                {selected.customers?.name ||
                  selected.customer_name ||
                  'Walk-in'}
              </b>
            </div>
            <div>
              <span>Status</span>
              <b>{selected.status || 'Processing'}</b>
            </div>
            <div>
              <span>Waiter</span>
              <b>{selected.waiter_name || selected.waiter?.name || '—'}</b>
            </div>
            <div>
              <span>Amount</span>
              <b>Rs {money(selected.grand_total ?? selected.total)}</b>
            </div>
          </div>

          <div className="ta-items">
            {(selected.order_items || []).length ? (
              selected.order_items.map(item => (
                <div key={item.id || `${item.name}-${item.qty}`}>
                  <span>
                    {item.qty || 1} × {item.name || 'Item'}
                  </span>
                  <b>
                    Rs{' '}
                    {money(
                      Number(item.qty || 0) *
                        Number(item.unit_price || 0)
                    )}
                  </b>
                </div>
              ))
            ) : (
              <div>No item details loaded for this order.</div>
            )}
          </div>
        </Modal>
      )}
    </div>
  )
}
