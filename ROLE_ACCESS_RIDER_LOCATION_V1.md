# Role access + Rider Location v1

- Order Taker / Waiter is hard-routed to `OrderTakerMobile` only.
- Delivery Boy / Rider is hard-routed to `DeliveryMobile` only.
- Role aliases are normalized before routing, so `waiter`, `order taker`, `rider`, and `delivery boy` cannot fall through to the desktop app.
- Order Taker no longer receives the general `pos.view` permission; it receives `waiter.app` plus the minimum order creation/edit/print/customer permissions used by the mobile workflow.
- Rider no longer receives `dashboard.view`; it keeps only own delivery/attendance/settings permissions.
- Added desktop management page **Rider Location** for Admin/Manager/Dispatcher permission `operations.dispatcher`.
- Rider Location reads the existing Supabase `nexa_live_riders` backend through `loadOperations`, refreshes every 15 seconds, shows GPS freshness, duty state, current token when available, and an OpenStreetMap position.
- Existing Rider mobile GPS continues to write through `nexa_rider_push_location` while the rider is on duty.
