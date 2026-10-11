# NEXA v26 POS + Delivery Fix

- POS header order: Cancelled, Draft, All, Delivery, Dine In, Take Away, Car Service, Third Party, Prepared, New Order.
- Added persistent POS Layout selector: Default Layout / Call Center Layout.
- Layout choice is saved in localStorage per browser/workstation.
- Delivery page now reads Delivery orders directly from `orders` as a fallback, so a valid Delivery order is visible even when its `deliveries` queue row is missing.
- Rider assignment / handover on a fallback row first calls `nexa_ensure_delivery_queue`, then continues the normal dispatch workflow.
- Migration 025 repairs existing missing queue rows and exposes the ensure RPC.
