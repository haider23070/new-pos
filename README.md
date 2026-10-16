# NEXA POS

This build uses the existing NEXA Supabase schema.

Required runtime tables include `profiles`, `branches`, `shifts`, `categories`, `menu_items`, `menu_variants`, `customers`, `restaurant_tables`, `orders`, `order_items`, `payments`, `riders`, and `deliveries`.

## Setup
1. Keep the existing `.env` Supabase URL/key for the correct project.
2. Run `npm install`.
3. Run `npm run dev`.

Do **not** create or run legacy `pos_*` tables. Payment is stored in `payments`; the UI derives payment time from `payments.created_at`.

If the app reports PGRST205/HTTP 404 for `public.profiles` while SQL confirms the table exists, check Supabase Dashboard → API settings → Exposed schemas and make sure `public` is exposed, then reload the PostgREST schema cache.
