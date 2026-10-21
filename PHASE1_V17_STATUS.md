# Mahir reference Phase 1 v17

Implemented distinct POS states for the supplied references: New Order, Running/All Orders, Cancelled, Draft, Dine In, Take Away, Delivery, Third Party, Car Service, plus the existing Mahir-style Profile Setting page.

Order-list pages now use the Mahir-style shortcut action strip (Edit Discount, View Bill, View Order, Edit Order, Print Bill, Make Payment) connected to NEXA's existing real order actions rather than decorative buttons. Each order-type tab has its own filtered workspace and state accent. Delivery now stays inside the same POS reference shell instead of switching to the unrelated operations panel.

NEXA remains an independent React/Supabase implementation. No Mahir credentials, CSRF values, tenant IDs, session values, or private endpoints are included.
