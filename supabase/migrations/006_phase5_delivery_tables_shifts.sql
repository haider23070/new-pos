-- NEXA Phase 5: Delivery/Riders + Tables + Shifts/Cash Handover
-- Self-contained: recreates branch helper so this migration can run safely after Phase 2.
create extension if not exists pgcrypto;
create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$
  select branch_id from public.users where auth_id=auth.uid() limit 1
$$;
grant execute on function public.nexa_my_branch() to authenticated;

-- Normalize/extend existing tables without destroying Phase 1 data.
alter table public.restaurant_tables add column if not exists floor_name text default 'Main Floor';
alter table public.restaurant_tables add column if not exists seats int default 4;
alter table public.restaurant_tables add column if not exists active boolean default true;
alter table public.restaurant_tables add column if not exists occupied_order_id uuid references public.orders(id) on delete set null;
alter table public.restaurant_tables add column if not exists occupied_at timestamptz;

alter table public.riders add column if not exists name text;
alter table public.riders add column if not exists phone text;
alter table public.riders add column if not exists status text default 'Available';
alter table public.riders add column if not exists checked_in_at timestamptz;
alter table public.riders add column if not exists checked_out_at timestamptz;

alter table public.deliveries add column if not exists branch_id uuid references public.branches(id) on delete cascade;
alter table public.deliveries add column if not exists customer_name text;
alter table public.deliveries add column if not exists customer_phone text;
alter table public.deliveries add column if not exists delivery_address text;
alter table public.deliveries add column if not exists rider_out_at timestamptz;
alter table public.deliveries add column if not exists rider_enter_at timestamptz;
alter table public.deliveries add column if not exists delivery_minutes int;
alter table public.deliveries add column if not exists notes text;
update public.deliveries d set branch_id=o.branch_id from public.orders o where d.order_id=o.id and d.branch_id is null;

alter table public.shifts add column if not exists opening_note text;
alter table public.shifts add column if not exists closing_note text;
alter table public.shifts add column if not exists cash_handover_to text;
alter table public.shifts add column if not exists cash_handover_amount numeric(14,2) default 0;
alter table public.shifts add column if not exists difference numeric(14,2) default 0;

create table if not exists public.shift_cash_movements(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.branches(id) on delete cascade,
 shift_id uuid not null references public.shifts(id) on delete cascade, type text not null check(type in('Cash In','Cash Out','Expense','Handover')),
 amount numeric(14,2) not null check(amount>=0), note text, created_by uuid references public.users(id), created_at timestamptz default now()
);
create table if not exists public.delivery_events(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.branches(id) on delete cascade,
 delivery_id uuid not null references public.deliveries(id) on delete cascade, event text not null, rider_id uuid references public.riders(id),
 note text, created_by uuid references public.users(id), created_at timestamptz default now()
);

-- RLS
alter table public.restaurant_tables enable row level security;
alter table public.riders enable row level security;
alter table public.deliveries enable row level security;
alter table public.shifts enable row level security;
alter table public.shift_cash_movements enable row level security;
alter table public.delivery_events enable row level security;

do $$ begin create policy "p5 tables branch" on public.restaurant_tables for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p5 riders branch" on public.riders for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p5 deliveries branch" on public.deliveries for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p5 shifts branch" on public.shifts for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p5 cash movements branch" on public.shift_cash_movements for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p5 delivery events branch" on public.delivery_events for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;

-- Realtime
alter table public.restaurant_tables replica identity full;
alter table public.riders replica identity full;
alter table public.deliveries replica identity full;
alter table public.shifts replica identity full;
do $$ begin alter publication supabase_realtime add table public.restaurant_tables; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.riders; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.deliveries; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.shifts; exception when duplicate_object then null; end $$;
