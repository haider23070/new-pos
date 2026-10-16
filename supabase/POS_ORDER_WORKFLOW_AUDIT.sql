-- NEXA POS: cancellation + discount audit fields used by the Mahir-style workflow UI.
-- Safe to run more than once.
alter table public.pos_orders add column if not exists cancelled_at timestamptz;
alter table public.pos_orders add column if not exists cancelled_by uuid;
alter table public.pos_orders add column if not exists cancel_authorized_by uuid;
alter table public.pos_orders add column if not exists cancel_reason text;
alter table public.pos_orders add column if not exists discount_reason text;
alter table public.pos_orders add column if not exists discount_type text;
alter table public.pos_orders add column if not exists discount_by uuid;

create index if not exists pos_orders_cancelled_at_idx on public.pos_orders(cancelled_at desc);
