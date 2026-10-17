# NEXA POS

This build uses the existing NEXA Supabase schema.

Required runtime tables include `profiles`, `branches`, `shifts`, `categories`, `menu_items`, `menu_variants`, `customers`, `restaurant_tables`, `orders`, `order_items`, `payments`, `riders`, and `deliveries`.

## Setup
1. Keep the existing `.env` Supabase URL/key for the correct project.
2. Run `npm install`.
3. Run `npm run dev`.

Do **not** create or run legacy `pos_*` tables. Payment is stored in `payments`; the UI derives payment time from `payments.created_at`.

If the app reports PGRST205/HTTP 404 for `public.profiles` while SQL confirms the table exists, check Supabase Dashboard → API settings → Exposed schemas and make sure `public` is exposed, then reload the PostgREST schema cache.

## NEXA Inventory v2
1. Run `supabase/NEXA_INVENTORY_SYSTEM.sql` if v1 has not been installed.
2. Then run `supabase/NEXA_INVENTORY_V2_COMPLETE.sql`.
3. Inventory v2 adds purchase orders/returns, supplier payable ledger, department/location foundations, demand/issuance/transfer workflow, direct ingredient sales, batches/expiry, recipe costing, low-stock purchasing data, and order-consumption reversal.
4. Existing permissive authenticated RLS policies are migration defaults; replace them with your production NEXA branch/role policy before deployment if your live project requires stricter database-level permissions.

## NEXA Inventory V2 completion
Inventory V2 now includes master setup (suppliers/departments/locations/recipe groups), PO approve/reject/receive, stock demand approval, purchasing/returns, transfer/issuance forms, production raw-material posting, physical closing, recipe costing, supplier payable reporting, low-stock demand, direct ingredient sales, and POS-paid recipe consumption with cancellation reversal.

For an existing V1 database, run `supabase/NEXA_INVENTORY_V2_COMPLETE.sql` again in Supabase SQL Editor so the V2.1 functions at the bottom are installed.
