# NEXA v25 Reference Workflow

Implemented against the four supplied UI references:
1. Call Center POS: running-orders-first split workspace with order panel on the right.
2. Default POS: vertical category rail, dense product/variant grid, fixed order panel.
3. Delivery: compact operational table with rider selector, handover, kitchen/delivery states and timers.
4. KDS: cumulative production list + dense multi-ticket kitchen board.

Critical workflow fix: migration `024_delivery_queue_workflow_fix.sql` creates/backfills a `deliveries` row for every non-draft Delivery order. This fixes Delivery orders being created in POS but never appearing on the Delivery screen. It also mirrors rider assignment and delivery status back to the order.
