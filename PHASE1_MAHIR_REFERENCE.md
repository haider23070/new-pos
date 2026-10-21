# NEXA POS — Mahir Reference Phase 1

Reference scope in this build: New Order, All/Processing Orders, Cancelled, Draft, Dine In, Take Away, Delivery, Third Party, Car Service and Profile/Workstation.

The implementation remains NEXA React + Supabase. Mahir saved pages/assets are reference material only and are not bundled into the app.

Functional behavior already wired in the NEXA source is preserved: order creation/draft, order view/edit, discount, cancellation, payment, receipt queueing, customer creation, realtime refresh, delivery operations, layout preference, receipt-printer preference and theme preference.

Build verification note: dependency installation timed out in the execution environment, so `vite build` could not be run because Vite was not installed locally. Run `npm install` then `npm run build` after extracting.
