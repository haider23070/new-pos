# NEXA Reports backend status

The Reports Center uses the supplied Mahir RMS screenshots as the directory/master reference, but NEXA styling and NEXA data rules.

## Live Supabase reports in this build
Food-sale/order reports read directly from `pos_orders`, `pos_order_items`, `pos_payments`, `pos_customers`, `pos_profiles`, `pos_categories`, and `pos_food_departments` for the selected branch and date range. They do not use the 500-order bootstrap cache.

Implemented live families include register/Z summary, invoice, item, variant, product, category, department, order type, date, cashier/waiter, customer, hourly, discounted, cancelled, top-customer, rider/delivery, product mix, peak-hours and revenue views. CSV export and print are included.

## Deliberately not faked
Purchase/stock/supplier/review/due/forecast/cost reports remain visible in the master directory but display a backend-not-enabled notice until their exact ledger/source tables are wired. This prevents invented financial or inventory figures.

No SQL migration is required for the live sales reports in this release.
