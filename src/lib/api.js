import { supabase, requireUser } from './supabase'

const ok = (result) => {
  if (result.error) throw result.error
  return result.data
}

const byId = (rows = []) => new Map(rows.map((row) => [row.id, row]))
const groupBy = (rows = [], key) => {
  const map = new Map()
  for (const row of rows) {
    const value = row[key]
    if (!map.has(value)) map.set(value, [])
    map.get(value).push(row)
  }
  return map
}

const paidAmount = (order) =>
  (order.payments || []).reduce((sum, p) => sum + Number(p.amount || 0), 0)

const normalizeOrder = (order) => {
  const payments = order.payments || []
  const paid = paidAmount(order)
  const total = Number(order.grand_total ?? order.total ?? 0)
  return {
    ...order,
    token_no: order.token_no,
    unique_id: order.unique_id || String(order.id || '').slice(0, 8).toUpperCase(),
    subtotal: Number(order.subtotal ?? order.total ?? 0),
    payment_status: (total > 0 && paid >= total - 0.001) ? 'PAID' : (String(order.payment_status || '').toUpperCase() === 'PAID' ? 'PAID' : 'UNPAID'),
    paid_at: [...payments].sort((a,b)=>new Date(b.created_at)-new Date(a.created_at))[0]?.created_at || null,
    payment_method: payments[0]?.method || null,
    pos_customers: order.customers || null,
    pos_order_items: (order.order_items || []).map((item) => ({
      ...item,
      name: item.name || item.item_name || item.product_name,
      qty: Number(item.qty ?? item.quantity ?? 0),
      line_total: Number(item.line_total ?? item.total ?? (Number(item.qty ?? item.quantity ?? 0) * Number(item.unit_price || 0))),
    })),
    pos_riders: order.rider || null,
    delivery_address: order.delivery_address || order.customers?.address || null,
  }
}

async function loadProfile(userId) {
  const result = await supabase
    .from('pos_profiles')
    .select('id,branch_id,name,email,role,active,created_at,receipt_printer_name,theme')
    .eq('id', userId)
    .maybeSingle()

  if (result.error) {
    const code = result.error.code || ''
    const message = result.error.message || 'Unknown Supabase error'
    // PGRST205 / HTTP 404 means PostgREST cannot see the table in its exposed schema cache.
    // This is intentionally reported as an API configuration problem instead of pretending
    // that the logged-in user has no profile.
    if (code === 'PGRST205' || /schema cache|could not find.*profiles/i.test(message)) {
      throw new Error(`Supabase REST API cannot expose public.profiles (${code || 'HTTP 404'}). The table exists in PostgreSQL, so check Supabase API > Exposed schemas includes public, then reload the PostgREST schema cache.`)
    }
    throw new Error(`Profile request failed${code ? ` [${code}]` : ''}: ${message}`)
  }

  const profile = result.data
  if (!profile) {
    throw new Error(`Login succeeded, but Auth user ${userId} has no matching row in public.profiles.`)
  }
  if (profile.active === false) throw new Error('This POS profile is inactive.')
  return profile
}

async function loadBranch(branchId) {
  if (!branchId) throw new Error('Your POS profile has no branch assigned.')
  const branch = ok(
    await supabase
      .from('pos_branches')
      .select('*')
      .eq('id', branchId)
      .maybeSingle()
  )
  if (!branch) throw new Error('The branch assigned to this profile does not exist.')
  return branch
}

async function loadRiders(branchId) {
  return ok(
    await supabase
      .from('pos_riders')
      .select('*')
      .eq('branch_id', branchId)
      .order('created_at', { ascending: false })
  )
}

async function loadOrders(branchId, riders) {
  const orders = ok(await supabase.from('pos_orders').select('*').eq('branch_id', branchId).order('created_at', { ascending: false }).limit(500))
  if (!orders.length) return []
  const orderIds = orders.map(o=>o.id)
  const customerIds = [...new Set(orders.map(o=>o.customer_id).filter(Boolean))]
  const [itemsResult,paymentsResult,customersResult] = await Promise.all([
    supabase.from('pos_order_items').select('*').in('order_id',orderIds),
    supabase.from('pos_payments').select('*').in('order_id',orderIds),
    customerIds.length ? supabase.from('pos_customers').select('*').in('id',customerIds) : Promise.resolve({data:[],error:null}),
  ])
  const itemsByOrder=groupBy(ok(itemsResult),'order_id')
  const paymentsByOrder=groupBy(ok(paymentsResult),'order_id')
  const customersMap=byId(ok(customersResult))
  const ridersMap=byId(riders)
  return orders.map(order=>normalizeOrder({
    ...order,
    customers: order.customer_id ? customersMap.get(order.customer_id)||null : null,
    order_items: itemsByOrder.get(order.id)||[],
    payments: paymentsByOrder.get(order.id)||[],
    rider: order.rider_id ? ridersMap.get(order.rider_id)||null : null,
  }))
}

export async function bootstrap() {
  const user = await requireUser()
  const profile = await loadProfile(user.id)
  const branch = await loadBranch(profile.branch_id)
  const branchId = branch.id

  const [catsResult, productsResult, customersResult, tablesResult, riders, shiftResult] = await Promise.all([
    supabase.from('pos_categories').select('*').eq('branch_id', branchId).eq('active', true).order('name'),
    supabase.from('pos_products').select('*').eq('branch_id', branchId).eq('active', true).order('name'),
    supabase.from('pos_customers').select('*').eq('branch_id', branchId).order('name'),
    supabase.from('pos_tables').select('*').eq('branch_id', branchId).order('name'),
    loadRiders(branchId),
    supabase.from('pos_shifts').select('*').eq('branch_id', branchId).eq('status', 'OPEN').order('opened_at', { ascending: false }).limit(1).maybeSingle(),
  ])

  const categories = ok(catsResult)
  const products = ok(productsResult)
  const customers = ok(customersResult)
  const tables = ok(tablesResult)
  const shift = ok(shiftResult)

  const productIds = products.map((p) => p.id)
  let variants = []
  if (productIds.length) {
    variants = ok(
      await supabase
        .from('pos_product_variants')
        .select('*')
        .in('product_id', productIds)
        .eq('active', true)
    )
  }
  const variantsByItem = groupBy(variants, 'product_id')
  const products2 = products.map((product) => ({
    ...product,
    menu_variants: variantsByItem.get(product.id) || [],
    pos_product_variants: (variantsByItem.get(product.id) || []).map((variant) => ({
      ...variant,
      sale_price: variant.price,
    })),
  }))

  const orders = await loadOrders(branchId, riders)

  const managersResult = await supabase
    .from('pos_profiles')
    .select('id,email,name,role,active')
    .eq('branch_id', branchId)
    .eq('active', true)
    .in('role', ['Admin', 'Manager'])

  const managers = managersResult.error ? [profile] : managersResult.data

  return {
    user,
    profile,
    branch,
    categories,
    products: products2,
    customers,
    tables,
    riders,
    orders,
    shift,
    managers,
  }
}

export async function createCustomer(branchId, input) {
  return ok(await supabase.from('pos_customers').insert({ ...input, branch_id: branchId }).select().single())
}

export async function saveOrder({ branchId, shiftId, customerId, tableId, riderId, type, notes, discount, cart, status = 'Processing' }) {
  const user = await requireUser()
  if (!shiftId) throw new Error('Open Day Shift before creating orders.')
  if (!cart.length) throw new Error('Add at least one item.')
  if (type === 'Dine-In' && !tableId) throw new Error('Select a table for Dine-In order.')

  const total = cart.reduce((sum, item) => sum + item.qty * item.price, 0)
  const grandTotal = Math.max(0, total - Number(discount || 0))

  // Allocate a visible token for every new order. The database trigger in
  // supabase/POS_TOKEN_NUMBERING.sql is the concurrency-safe source of truth;
  // this client-side value also keeps token assignment working immediately.
  const lastTokenResult = await supabase
    .from('pos_orders')
    .select('token_no')
    .eq('branch_id', branchId)
    .eq('shift_id', shiftId)
    .not('token_no', 'is', null)
    .order('token_no', { ascending: false })
    .limit(1)
  if (lastTokenResult.error) throw lastTokenResult.error
  const tokenNo = Number(lastTokenResult.data?.[0]?.token_no || 0) + 1

  const order = ok(
    await supabase
      .from('pos_orders')
      .insert({
        branch_id: branchId,
        token_no: tokenNo,
        shift_id: shiftId,
        customer_id: customerId || null,
        table_id: tableId || null,
        rider_id: riderId || null,
        order_type: type,
        status,
        kitchen_status: 'Pending',
        total,
        discount: Number(discount || 0),
        grand_total: grandTotal,
        notes: notes || null,
        delivery_status: type === 'Delivery' ? (riderId ? 'Rider Assigned' : 'Awaiting Rider') : null,
        created_by: user.id,
      })
      .select()
      .single()
  )

  const items = cart.map((item) => ({
    order_id: order.id,
    product_id: item.product_id,
    variant_id: item.variant_id,
    name: item.name + (item.size ? ` - ${item.size}` : ''),
    qty: item.qty,
    unit_price: item.price,
  }))
  ok(await supabase.from('pos_order_items').insert(items))

  return order
}

export async function updateExistingOrder(orderId, { customerId, tableId, riderId, type, reference, notes, discount, cart }) {
  if (!orderId) throw new Error('Order id is required.')
  if (!cart?.length) throw new Error('Add at least one item.')
  if (type === 'Dine-In' && !tableId) throw new Error('Select a table for Dine-In order.')
  const total = cart.reduce((sum, item) => sum + Number(item.qty || 0) * Number(item.price || 0), 0)
  const grandTotal = Math.max(0, total - Number(discount || 0))
  ok(await supabase.from('pos_orders').update({
    customer_id: customerId || null, table_id: type === 'Dine-In' ? (tableId || null) : null,
    rider_id: riderId || null, order_type: type, reference: reference || null, notes: notes || null, total,
    discount: Number(discount || 0), grand_total: grandTotal, updated_at: new Date().toISOString()
  }).eq('id', orderId))
  ok(await supabase.from('pos_order_items').delete().eq('order_id', orderId))
  const items = cart.map(item => ({order_id: orderId, product_id: item.product_id || null, variant_id: item.variant_id || null, name: item.name + (item.size ? ` - ${item.size}` : ''), qty: Number(item.qty || 1), unit_price: Number(item.price || 0)}))
  ok(await supabase.from('pos_order_items').insert(items))
  return ok(await supabase.from('pos_orders').select('*').eq('id', orderId).single())
}

export async function payOrder(orderId, method = 'Cash', amount = null) {
  const user = await requireUser()
  const order = ok(await supabase.from('pos_orders').select('*').eq('id', orderId).single())
  const payments = ok(await supabase.from('pos_payments').select('*').eq('order_id', orderId))
  const alreadyPaid = paidAmount({ payments })
  const grandTotal = Number(order.grand_total ?? order.total ?? 0)
  if (!Number.isFinite(grandTotal) || grandTotal <= 0) {
    throw new Error('Order total is missing or invalid. Cannot take payment.')
  }
  // pos_payments is the source of truth for money actually received.
  // Some legacy/unpaid orders have a stale paid_amount equal to the order total,
  // which must NOT make them look paid when there is no payment row.
  const effectivePaid = alreadyPaid
  const due = Math.max(0, grandTotal - effectivePaid)
  const paymentAmount = amount == null ? due : Number(amount)

  if (due <= 0.001) throw new Error('This order is already fully paid.')
  if (!Number.isFinite(paymentAmount) || paymentAmount <= 0) throw new Error('Enter a valid payment amount.')
  if (paymentAmount > due + 0.001) throw new Error(`Payment cannot exceed remaining balance of Rs ${due.toFixed(2)}.`)

  ok(
    await supabase.from('pos_payments').insert({
      order_id: orderId,
      branch_id: order.branch_id,
      shift_id: order.shift_id,
      amount: paymentAmount,
      method,
      received_by: user.id,
    })
  )

  const fullyPaid = effectivePaid + paymentAmount >= grandTotal - 0.001
  if (fullyPaid) {
    // Every fully-paid order must be marked PAID, regardless of order type.
    // Delivery can keep its operational delivery status while disappearing from
    // unpaid/POS order lists. Dine-In and Take-Away are completed on payment.
    const patch = {
      payment_status: 'PAID',
      paid_amount: grandTotal,
    }
    if (order.order_type !== 'Delivery') patch.status = 'Completed'
    ok(await supabase.from('pos_orders').update(patch).eq('id', orderId).select().single())
  }

  return { paid: paymentAmount, due: Math.max(0, due - paymentAmount), fullyPaid }
}

export async function updateOrderStatus(id, patch) {
  const allowed = ['status', 'kitchen_status', 'delivery_status', 'discount', 'grand_total', 'notes', 'remarks', 'rider_id', 'paid_amount', 'payment_status', 'cancelled_at', 'cancelled_by', 'cancel_authorized_by', 'cancel_reason', 'discount_reason', 'discount_type', 'discount_by']
  const clean = Object.fromEntries(Object.entries(patch).filter(([key]) => allowed.includes(key)))
  return ok(await supabase.from('pos_orders').update(clean).eq('id', id).select().single())
}

export async function assignRider(orderId, riderId) {
  return ok(await supabase.from('pos_orders').update({
    rider_id: riderId || null,
    delivery_status: riderId ? 'Rider Assigned' : 'Awaiting Rider',
  }).eq('id', orderId).select().single())
}

export async function openShift(branchId) {
  const user = await requireUser()
  const existing = ok(
    await supabase.from('pos_shifts').select('*').eq('branch_id', branchId).eq('status', 'OPEN').order('opened_at', { ascending: false }).limit(1).maybeSingle()
  )
  if (existing) return existing
  return ok(await supabase.from('pos_shifts').insert({ branch_id: branchId, opened_by: user.id, status: 'OPEN', opening_cash: 0 }).select().single())
}

export async function cashHandover(shiftId, branchId, amount, notes) {
  const user = await requireUser()
  if (!shiftId) throw new Error('No open shift.')
  return ok(
    await supabase
      .from('pos_cash_handovers')
      .insert({ shift_id: shiftId, branch_id: branchId, amount: Number(amount), notes, handed_over_by: user.id })
      .select()
      .single()
  )
}

export async function shiftSummary(shiftId) {
  if (!shiftId) return { sales: 0, cash: 0, card: 0, handovers: 0 }

  const orders = ok(await supabase.from('pos_orders').select('id,grand_total,status').eq('shift_id', shiftId))
  const orderIds = orders.map((o) => o.id)
  const payments = orderIds.length
    ? ok(await supabase.from('pos_payments').select('amount,method').in('order_id', orderIds))
    : []
  const handovers = ok(await supabase.from('pos_cash_handovers').select('amount').eq('shift_id', shiftId))
  const activePayments = payments

  return {
    sales: orders.filter((o) => String(o.status).toLowerCase() !== 'cancelled').reduce((sum, o) => sum + Number(o.grand_total || 0), 0),
    cash: activePayments.filter((p) => p.method === 'Cash').reduce((sum, p) => sum + Number(p.amount || 0), 0),
    card: activePayments.filter((p) => p.method === 'Card').reduce((sum, p) => sum + Number(p.amount || 0), 0),
    handovers: handovers.reduce((sum, x) => sum + Number(x.amount || 0), 0),
  }
}

export async function closeShift(shiftId, closingCash) {
  const user = await requireUser()
  if (!shiftId) throw new Error('No open shift.')

  const pending = await supabase
    .from('pos_orders')
    .select('id', { count: 'exact', head: true })
    .eq('shift_id', shiftId)
    .not('status', 'in', '("Completed","Cancelled")')

  if (pending.error) throw pending.error
  if ((pending.count || 0) > 0) throw new Error('Pending orders must be completed or cancelled before closing shift.')

  return ok(
    await supabase
      .from('pos_shifts')
      .update({
        status: 'CLOSED',
        closed_at: new Date().toISOString(),
        closed_by: user.id,
        closing_cash: Number(closingCash || 0),
      })
      .eq('id', shiftId)
      .select()
      .single()
  )
}

export function subscribe(branchId, refresh) {
  if (!supabase || !branchId) return () => {}
  const channel = supabase
    .channel(`nexa-pos-live-${branchId}`)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pos_orders', filter: `branch_id=eq.${branchId}` }, refresh)
    .on('postgres_changes', { event: '*', schema: 'public', table: 'pos_payments' }, refresh)
    .subscribe()

  return () => supabase.removeChannel(channel)
}
