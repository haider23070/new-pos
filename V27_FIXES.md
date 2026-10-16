# NEXA v27 fixes
- Cancelled orders now appear only in the Cancelled POS tab; they are excluded from All, Take Away, Delivery, Prepared and other operational tabs.
- Delivery order loading excludes cancelled orders and refreshes when the `orders` table changes.
- Migration 026 creates missing `riders` rows for active Delivery Boy profiles so attendance/dispatch use the same rider identity.
- Default POS keeps the cart/customer/checkout panel visible on normal desktop widths and uses the reference vertical category/product workspace.
- Order list filter toolbar and Delivery rider/hand-over cells have repaired sizing/overflow.
