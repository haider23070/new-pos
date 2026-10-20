# NEXA Waiter / Order Taker App v1

Implemented as a role-specific mobile interface for `Order Taker` and `Waiter` profiles.

- Mobile menu categories and item/variant selection
- Live Supabase menu, variants, prices and deals
- Deal component details in item cards and cart
- Cart quantity controls and totals
- Dine-In / Take-Away selection
- Mandatory table selection for Dine-In
- Order notes, kitchen notes and covers
- Draft and Place Order using the existing `saveOrder()` backend
- Existing KOT / department printer routing is therefore reused automatically
- Mobile order list with All/Pending/Processing/Ready filters
- Order detail modal and order history access
- Restricted waiter navigation and logout

No new database schema is required for this first waiter build. It uses the existing NEXA POS tables and order workflow.
