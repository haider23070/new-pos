import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })

  let createdUserId: string | null = null
  try {
    const url = Deno.env.get('SUPABASE_URL')!
    const anon = Deno.env.get('SUPABASE_ANON_KEY')!
    const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const auth = createClient(url, anon, { global: { headers: { Authorization: req.headers.get('Authorization') || '' } } })
    const admin = createClient(url, service)

    const { data: { user }, error: userError } = await auth.auth.getUser()
    if (userError || !user) throw new Error('Authentication required')

    // NEXA uses pos_profiles, not the legacy profiles table.
    const { data: caller, error: callerError } = await admin
      .from('pos_profiles')
      .select('id,role,branch_id,active')
      .eq('id', user.id)
      .single()
    if (callerError) throw callerError
    if (!caller?.active || !['Developer', 'Admin', 'Manager'].includes(caller.role)) {
      throw new Error('Only Developer, Admin or Manager can add staff')
    }

    const body = await req.json()
    const name = String(body.name || '').trim()
    const email = String(body.email || '').trim().toLowerCase()
    const password = String(body.password || '')
    const role = String(body.role || '').trim()
    const phone = String(body.phone || '').trim() || null

    if (!name) throw new Error('Name is required')
    if (!email) throw new Error('Email is required')
    if (password.length < 8) throw new Error('Password must be at least 8 characters')

    const allowed = ['Manager', 'Cashier', 'Call Center', 'Dispatcher', 'Delivery Boy', 'Order Taker', 'Kitchen Staff']
    if (['Developer', 'Admin'].includes(caller.role)) allowed.unshift('Admin')
    if (caller.role === 'Developer') allowed.unshift('Developer')
    if (!allowed.includes(role)) throw new Error('Role not allowed')

    const targetBranch = caller.role === 'Manager' ? caller.branch_id : (body.branch_id || caller.branch_id)
    if (!targetBranch) throw new Error('Branch is required')

    const { data: created, error: createError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { name, role },
    })
    if (createError) throw createError
    createdUserId = created.user.id

    // Only write columns that really exist in the confirmed pos_profiles schema.
    const { error: profileError } = await admin.from('pos_profiles').upsert({
      id: created.user.id,
      email,
      name,
      role,
      branch_id: targetBranch,
      active: body.active !== false,
      receipt_printer_name: body.receipt_printer_name || null,
    }, { onConflict: 'id' })
    if (profileError) throw profileError

    let riderId: string | null = null
    if (role === 'Delivery Boy') {
      // Reuse an existing unlinked rider when possible, otherwise create one.
      // This makes old rider records and all future rider accounts work without manual UUID linking.
      let existing: any = null
      if (phone) {
        const { data } = await admin.from('pos_riders')
          .select('id,profile_id')
          .eq('branch_id', targetBranch)
          .eq('phone', phone)
          .is('profile_id', null)
          .limit(1)
          .maybeSingle()
        existing = data
      }
      if (!existing) {
        const { data } = await admin.from('pos_riders')
          .select('id,profile_id')
          .eq('branch_id', targetBranch)
          .ilike('name', name)
          .is('profile_id', null)
          .limit(1)
          .maybeSingle()
        existing = data
      }

      if (existing?.id) {
        const { error } = await admin.from('pos_riders').update({
          profile_id: created.user.id,
          name,
          phone,
          active: body.active !== false,
          status: 'Available',
          on_duty: false,
          updated_at: new Date().toISOString(),
        }).eq('id', existing.id)
        if (error) throw error
        riderId = existing.id
      } else {
        const { data: rider, error } = await admin.from('pos_riders').insert({
          branch_id: targetBranch,
          name,
          phone,
          active: body.active !== false,
          status: 'Available',
          profile_id: created.user.id,
          on_duty: false,
          cash_balance: 0,
        }).select('id').single()
        if (error) throw error
        riderId = rider.id
      }
    }

    return new Response(JSON.stringify({
      id: created.user.id,
      email,
      role,
      rider_id: riderId,
      rider_linked: role === 'Delivery Boy' ? !!riderId : undefined,
    }), { headers: { ...cors, 'Content-Type': 'application/json' } })
  } catch (e) {
    // Avoid leaving a half-created login if profile/rider creation fails.
    if (createdUserId) {
      try {
        const url = Deno.env.get('SUPABASE_URL')!
        const service = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const admin = createClient(url, service)
        await admin.auth.admin.deleteUser(createdUserId)
      } catch (_) { /* best-effort rollback */ }
    }
    return new Response(JSON.stringify({ error: e instanceof Error ? e.message : String(e) }), {
      status: 400,
      headers: { ...cors, 'Content-Type': 'application/json' },
    })
  }
})
