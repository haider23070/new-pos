-- NEXA COMPLETE BACKEND - FRESH SUPABASE INSTALL
-- Run this whole file once in a NEW Supabase SQL Editor.


-- ===== SOURCE: 001_nexa_core.sql =====
-- NEXA Restaurant Management System - core schema
create extension if not exists pgcrypto;
create table if not exists organizations(id uuid primary key default gen_random_uuid(),name text not null,created_at timestamptz default now());
create table if not exists branches(id uuid primary key default gen_random_uuid(),organization_id uuid references organizations on delete cascade,name text not null,address text,phone text,active boolean default true,created_at timestamptz default now());
create table if not exists profiles(id uuid primary key references auth.users on delete cascade,branch_id uuid references branches,name text,email text,role text not null default 'Cashier',pin_hash text,active boolean default true,created_at timestamptz default now());
create table if not exists permissions(id uuid primary key default gen_random_uuid(),code text unique not null,label text not null);
create table if not exists role_permissions(role text not null,permission_id uuid references permissions on delete cascade,primary key(role,permission_id));
create table if not exists categories(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,name text not null,department text,active boolean default true,sort_order int default 0);
create table if not exists menu_items(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,category_id uuid references categories,name text not null,sku text,active boolean default true,created_at timestamptz default now());
create table if not exists menu_variants(id uuid primary key default gen_random_uuid(),item_id uuid references menu_items on delete cascade,name text not null,price numeric(12,2) not null default 0,is_default boolean default false,active boolean default true);
create table if not exists addons(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,name text not null,price numeric(12,2) default 0,active boolean default true);
create table if not exists customers(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,name text,phone text,address text,balance numeric(12,2) default 0,created_at timestamptz default now());
create table if not exists restaurant_tables(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,name text not null,capacity int default 4,status text default 'Available');
create table if not exists shifts(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,opened_by uuid references profiles,opened_at timestamptz default now(),opening_cash numeric(12,2) default 0,closed_by uuid references profiles,closed_at timestamptz,expected_cash numeric(12,2),actual_cash numeric(12,2),status text default 'Open');
create table if not exists orders(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,shift_id uuid references shifts,customer_id uuid references customers,table_id uuid references restaurant_tables,token bigint,invoice_no text,order_type text not null,status text default 'Draft',kitchen_status text default 'Pending',delivery_status text,total numeric(12,2) default 0,discount numeric(12,2) default 0,tax numeric(12,2) default 0,grand_total numeric(12,2) default 0,created_by uuid references profiles,created_at timestamptz default now(),completed_at timestamptz,cancel_reason text);
create table if not exists order_items(id uuid primary key default gen_random_uuid(),order_id uuid references orders on delete cascade,item_id uuid references menu_items,variant_id uuid references menu_variants,name text not null,qty numeric(12,3) not null,unit_price numeric(12,2) not null,status text default 'Pending',notes text);
create table if not exists payments(id uuid primary key default gen_random_uuid(),order_id uuid references orders,method text not null,amount numeric(12,2) not null,status text default 'Paid',received_by uuid references profiles,created_at timestamptz default now(),reversed_at timestamptz,reversal_reason text);
create table if not exists kitchen_departments(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,name text not null,printer_name text,active boolean default true);
create table if not exists riders(id uuid primary key default gen_random_uuid(),profile_id uuid references profiles,branch_id uuid references branches,on_duty boolean default false,cash_balance numeric(12,2) default 0);
create table if not exists deliveries(id uuid primary key default gen_random_uuid(),order_id uuid references orders unique,rider_id uuid references riders,status text default 'Awaiting Rider',assigned_at timestamptz,handed_over_at timestamptz,delivered_at timestamptz);
create table if not exists ingredients(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,name text not null,unit text not null,quantity numeric(14,3) default 0,min_quantity numeric(14,3) default 0,cost numeric(12,2) default 0,active boolean default true);
create table if not exists recipes(id uuid primary key default gen_random_uuid(),variant_id uuid references menu_variants on delete cascade,ingredient_id uuid references ingredients,quantity numeric(14,3) not null,unique(variant_id,ingredient_id));
create table if not exists stock_movements(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,ingredient_id uuid references ingredients,type text not null,quantity numeric(14,3) not null,reference_type text,reference_id uuid,notes text,created_by uuid references profiles,created_at timestamptz default now());
create table if not exists suppliers(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,name text not null,phone text,address text,balance numeric(12,2) default 0);
create table if not exists purchases(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,supplier_id uuid references suppliers,status text default 'Draft',total numeric(12,2) default 0,created_by uuid references profiles,created_at timestamptz default now());
create table if not exists purchase_items(id uuid primary key default gen_random_uuid(),purchase_id uuid references purchases on delete cascade,ingredient_id uuid references ingredients,qty numeric(14,3),unit_cost numeric(12,2));
create table if not exists expenses(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,shift_id uuid references shifts,category text,description text,amount numeric(12,2) not null,created_by uuid references profiles,created_at timestamptz default now());
create table if not exists audit_log(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,actor_id uuid references profiles,action text not null,entity_type text,entity_id uuid,reason text,metadata jsonb default '{}'::jsonb,created_at timestamptz default now());
create table if not exists notifications(id uuid primary key default gen_random_uuid(),branch_id uuid references branches,user_id uuid references profiles,title text,message text,read_at timestamptz,created_at timestamptz default now());
-- RLS baseline: authenticated users can only access their branch. Tighten privileged writes with RPCs before production.
alter table profiles enable row level security; alter table orders enable row level security; alter table order_items enable row level security; alter table payments enable row level security; alter table ingredients enable row level security; alter table stock_movements enable row level security;
create policy "profile self read" on profiles for select to authenticated using(id=auth.uid());
create policy "branch orders read" on orders for select to authenticated using(branch_id=(select branch_id from profiles where id=auth.uid()));
create policy "branch orders insert" on orders for insert to authenticated with check(branch_id=(select branch_id from profiles where id=auth.uid()));


-- ===== SOURCE: 002_nexa_full_system.sql =====
-- NEXA full restaurant operational schema (run after 001_nexa_core.sql)
create extension if not exists pgcrypto;

create table if not exists public.roles(id uuid primary key default gen_random_uuid(), name text unique not null, permissions jsonb not null default '{}'::jsonb, created_at timestamptz default now());
create table if not exists public.user_roles(user_id uuid not null, role_id uuid references public.roles(id) on delete cascade, branch_id uuid, primary key(user_id,role_id,branch_id));
create table if not exists public.manager_authorizations(id uuid primary key default gen_random_uuid(), branch_id uuid, requested_by uuid, authorized_by uuid, action text not null, entity_type text, entity_id uuid, reason text, created_at timestamptz default now());
create table if not exists public.floors(id uuid primary key default gen_random_uuid(), branch_id uuid not null, name text not null, active boolean default true);
create table if not exists public.restaurant_tables(id uuid primary key default gen_random_uuid(), branch_id uuid not null, floor_id uuid references public.floors(id), name text not null, seats int default 4, status text default 'available' check(status in('available','occupied','reserved','disabled')), active boolean default true);
create table if not exists public.riders(id uuid primary key default gen_random_uuid(), branch_id uuid not null, user_id uuid, name text not null, phone text, status text default 'off_duty' check(status in('off_duty','available','assigned','on_delivery')), active boolean default true);
create table if not exists public.delivery_events(id uuid primary key default gen_random_uuid(), order_id uuid not null, rider_id uuid references public.riders(id), status text not null, notes text, created_by uuid, created_at timestamptz default now());
create table if not exists public.shifts(id uuid primary key default gen_random_uuid(), branch_id uuid not null, opened_by uuid, closed_by uuid, opened_at timestamptz default now(), closed_at timestamptz, opening_cash numeric(14,2) default 0, expected_cash numeric(14,2) default 0, closing_cash numeric(14,2), difference numeric(14,2), status text default 'open' check(status in('open','closed')), notes text);
create table if not exists public.cash_movements(id uuid primary key default gen_random_uuid(), branch_id uuid not null, shift_id uuid references public.shifts(id), type text not null check(type in('opening','sale','refund','expense','cash_in','cash_out','closing')), amount numeric(14,2) not null, reference_type text, reference_id uuid, notes text, created_by uuid, created_at timestamptz default now());
create table if not exists public.suppliers(id uuid primary key default gen_random_uuid(), branch_id uuid, name text not null, phone text, email text, address text, opening_balance numeric(14,2) default 0, active boolean default true, created_at timestamptz default now());
create table if not exists public.purchase_orders(id uuid primary key default gen_random_uuid(), branch_id uuid not null, supplier_id uuid references public.suppliers(id), po_no bigint generated by default as identity, status text default 'draft' check(status in('draft','ordered','partial','received','cancelled')), subtotal numeric(14,2) default 0, discount numeric(14,2) default 0, total numeric(14,2) default 0, paid numeric(14,2) default 0, notes text, created_by uuid, created_at timestamptz default now(), received_at timestamptz);
create table if not exists public.purchase_items(id uuid primary key default gen_random_uuid(), purchase_id uuid references public.purchase_orders(id) on delete cascade, ingredient_id uuid, qty numeric(14,3) not null, unit text, unit_cost numeric(14,2) not null, received_qty numeric(14,3) default 0);
create table if not exists public.recipes(id uuid primary key default gen_random_uuid(), menu_item_id uuid not null, variant_id uuid, yield_qty numeric(14,3) default 1, active boolean default true);
create table if not exists public.recipe_items(id uuid primary key default gen_random_uuid(), recipe_id uuid references public.recipes(id) on delete cascade, ingredient_id uuid not null, qty numeric(14,3) not null, unit text not null);
create table if not exists public.stock_transfers(id uuid primary key default gen_random_uuid(), from_branch_id uuid not null, to_branch_id uuid not null, status text default 'draft' check(status in('draft','sent','received','cancelled')), created_by uuid, received_by uuid, created_at timestamptz default now(), received_at timestamptz);
create table if not exists public.stock_transfer_items(id uuid primary key default gen_random_uuid(), transfer_id uuid references public.stock_transfers(id) on delete cascade, ingredient_id uuid not null, qty numeric(14,3) not null, unit text not null);
create table if not exists public.wastage(id uuid primary key default gen_random_uuid(), branch_id uuid not null, ingredient_id uuid, menu_item_id uuid, qty numeric(14,3) not null, unit text, cost numeric(14,2) default 0, reason text not null, approved_by uuid, created_by uuid, created_at timestamptz default now());
create table if not exists public.expense_categories(id uuid primary key default gen_random_uuid(), name text unique not null, active boolean default true);
create table if not exists public.expenses(id uuid primary key default gen_random_uuid(), branch_id uuid not null, shift_id uuid references public.shifts(id), category_id uuid references public.expense_categories(id), amount numeric(14,2) not null, description text, payment_method text default 'cash', created_by uuid, approved_by uuid, created_at timestamptz default now());
create table if not exists public.ledger_entries(id uuid primary key default gen_random_uuid(), branch_id uuid not null, account_type text not null, account_id uuid, entry_type text not null, amount numeric(14,2) not null, reference_type text, reference_id uuid, description text, reversed_at timestamptz, reverses_entry_id uuid references public.ledger_entries(id), created_by uuid, created_at timestamptz default now());
create table if not exists public.printers(id uuid primary key default gen_random_uuid(), branch_id uuid not null, name text not null, system_name text, printer_type text default 'thermal', paper_width_mm int default 80, department_id uuid, auto_print boolean default false, copies int default 1, active boolean default true);
create table if not exists public.notifications(id uuid primary key default gen_random_uuid(), branch_id uuid, user_id uuid, type text, title text not null, body text, read_at timestamptz, created_at timestamptz default now());
create table if not exists public.audit_log(id uuid primary key default gen_random_uuid(), branch_id uuid, user_id uuid, action text not null, entity_type text, entity_id uuid, before_data jsonb, after_data jsonb, reason text, created_at timestamptz default now());
create table if not exists public.app_settings(id uuid primary key default gen_random_uuid(), branch_id uuid, key text not null, value jsonb not null default '{}'::jsonb, updated_by uuid, updated_at timestamptz default now(), unique(branch_id,key));

insert into public.roles(name,permissions) values
('Developer','{"all":true}'),('Admin','{"manage_branch":true,"manage_users":true,"reverse":true}'),('Manager','{"pos":true,"kds":true,"shift":true,"authorize":true}'),('Cashier','{"pos":true,"payments":true}'),('Kitchen','{"kds":true}'),('Store Keeper','{"inventory":true,"purchasing":true}'),('Rider','{"delivery":true}'),('Accountant','{"accounting":true,"reports":true}') on conflict(name) do nothing;

-- Generic authenticated access foundation. Tighten branch policies after creating your first admin/user mapping.
do $$ declare t text; begin
foreach t in array array['roles','user_roles','manager_authorizations','floors','restaurant_tables','riders','delivery_events','shifts','cash_movements','suppliers','purchase_orders','purchase_items','recipes','recipe_items','stock_transfers','stock_transfer_items','wastage','expense_categories','expenses','ledger_entries','printers','notifications','audit_log','app_settings'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('drop policy if exists authenticated_all on public.%I',t);
 execute format('create policy authenticated_all on public.%I for all to authenticated using (true) with check (true)',t);
end loop; end $$;


-- ===== SOURCE: 003_phase2_auth_roles_rls.sql =====
-- NEXA Phase 2: Authentication, branches, roles, permissions and RLS
create extension if not exists pgcrypto;

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text unique,
  address text,
  phone text,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);
insert into public.roles(name) values
 ('Developer'),('Admin'),('Manager'),('Cashier'),('Waiter'),('Kitchen'),('Store Keeper'),('Rider'),('Accountant')
on conflict(name) do nothing;

create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  auth_id uuid unique references auth.users(id) on delete cascade,
  branch_id uuid references public.branches(id),
  email text,
  name text,
  full_name text,
  phone text,
  role text,
  status text not null default 'Active' check(status in ('Active','Inactive')),
  pin_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.user_roles (
  user_id uuid not null references public.users(id) on delete cascade,
  role_id uuid not null references public.roles(id) on delete cascade,
  primary key(user_id,role_id)
);

create table if not exists public.user_branch_mappings (
  user_id uuid not null references public.users(id) on delete cascade,
  branch_id uuid not null references public.branches(id) on delete cascade,
  primary key(user_id,branch_id)
);

create table if not exists public.user_permissions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  permission_key text not null,
  allowed boolean not null default true,
  unique(user_id,permission_key)
);

create or replace function public.current_app_user()
returns public.users language sql stable security definer set search_path=public as $$
  select * from public.users where auth_id=auth.uid() limit 1
$$;
create or replace function public.current_branch_id()
returns uuid language sql stable security definer set search_path=public as $$
  select branch_id from public.users where auth_id=auth.uid() limit 1
$$;
create or replace function public.current_role()
returns text language sql stable security definer set search_path=public as $$
  select coalesce(r.name,u.role) from public.users u
  left join public.user_roles ur on ur.user_id=u.id
  left join public.roles r on r.id=ur.role_id
  where u.auth_id=auth.uid() limit 1
$$;
create or replace function public.is_management()
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(public.current_role() in ('Developer','Admin','Manager'),false)
$$;
create or replace function public.can_access_branch(target uuid)
returns boolean language sql stable security definer set search_path=public as $$
  select coalesce(public.current_role()='Developer' or target=public.current_branch_id() or exists(
    select 1 from public.user_branch_mappings m join public.users u on u.id=m.user_id
    where u.auth_id=auth.uid() and m.branch_id=target
  ),false)
$$;

alter table public.branches enable row level security;
alter table public.users enable row level security;
alter table public.roles enable row level security;
alter table public.user_roles enable row level security;
alter table public.user_branch_mappings enable row level security;
alter table public.user_permissions enable row level security;

drop policy if exists branches_read on public.branches;
create policy branches_read on public.branches for select to authenticated using(public.can_access_branch(id));
drop policy if exists users_read on public.users;
create policy users_read on public.users for select to authenticated using(auth_id=auth.uid() or (public.is_management() and public.can_access_branch(branch_id)));
drop policy if exists users_manage on public.users;
create policy users_manage on public.users for update to authenticated using(public.is_management() and public.can_access_branch(branch_id)) with check(public.is_management() and public.can_access_branch(branch_id));
drop policy if exists roles_read on public.roles;
create policy roles_read on public.roles for select to authenticated using(true);
drop policy if exists user_roles_read on public.user_roles;
create policy user_roles_read on public.user_roles for select to authenticated using(true);
drop policy if exists mappings_read on public.user_branch_mappings;
create policy mappings_read on public.user_branch_mappings for select to authenticated using(true);
drop policy if exists permissions_read on public.user_permissions;
create policy permissions_read on public.user_permissions for select to authenticated using(user_id=(select id from public.users where auth_id=auth.uid()) or public.is_management());

-- Apply branch isolation to existing Phase 1/Full-System tables when they exist.
do $$ declare t text; begin
  foreach t in array array['orders','order_items','payments','inventory','inventory_movements','purchases','expenses','shifts','deliveries','audit_logs','notifications'] loop
    if to_regclass('public.'||t) is not null then execute format('alter table public.%I enable row level security',t); end if;
  end loop;
end $$;


-- ===== SOURCE: 004_phase3_complete_pos.sql =====
-- NEXA Phase 3: POS persistence, numbering and branch RLS
alter table public.orders add column if not exists notes text;
alter table public.orders add column if not exists updated_at timestamptz default now();
create sequence if not exists public.nexa_order_token_seq start 1;
create or replace function public.nexa_set_order_numbers() returns trigger language plpgsql as $$
begin
 if new.token is null then new.token := nextval('public.nexa_order_token_seq'); end if;
 if new.invoice_no is null then new.invoice_no := 'NX-'||to_char(now(),'YYMMDD')||'-'||lpad(new.token::text,5,'0'); end if;
 return new;
end $$;
drop trigger if exists trg_nexa_order_numbers on public.orders;
create trigger trg_nexa_order_numbers before insert on public.orders for each row execute function public.nexa_set_order_numbers();

alter table public.categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.menu_variants enable row level security;
alter table public.customers enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$ select branch_id from public.users where auth_id=auth.uid() limit 1 $$;

do $$ begin
 create policy "p3 categories read" on public.categories for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 menu read" on public.menu_items for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 variants read" on public.menu_variants for select to authenticated using(exists(select 1 from public.menu_items m where m.id=item_id and m.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 customers all" on public.customers for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 tables read" on public.restaurant_tables for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 orders update" on public.orders for update to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 orderitems read" on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 orderitems insert" on public.order_items for insert to authenticated with check(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 payments read" on public.payments for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 payments insert" on public.payments for insert to authenticated with check(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;

alter table public.orders replica identity full;
do $$ begin alter publication supabase_realtime add table public.orders; exception when duplicate_object then null; end $$;


-- ===== SOURCE: 005_phase4_kitchen_kds_printing.sql =====
-- NEXA Phase 4: Kitchen, KDS, KOT and print queue
alter table public.orders add column if not exists prepared_at timestamptz;
alter table public.orders add column if not exists served_at timestamptz;
alter table public.order_items add column if not exists kitchen_updated_at timestamptz;
create table if not exists public.kitchen_departments(id uuid primary key default gen_random_uuid(),branch_id uuid not null references public.branches(id) on delete cascade,name text not null,description text,active boolean default true,created_at timestamptz default now(),unique(branch_id,name));
create table if not exists public.printer_settings(id uuid primary key default gen_random_uuid(),branch_id uuid not null references public.branches(id) on delete cascade,name text not null,printer_name text,department_id uuid references public.kitchen_departments(id) on delete set null,paper_width_mm int default 80,auto_print boolean default true,active boolean default true,created_at timestamptz default now());
create table if not exists public.kitchen_tickets(id uuid primary key default gen_random_uuid(),branch_id uuid not null references public.branches(id) on delete cascade,order_id uuid not null references public.orders(id) on delete cascade,department_id uuid references public.kitchen_departments(id),token bigint,status text default 'Processing',created_by uuid,created_at timestamptz default now(),prepared_at timestamptz,served_at timestamptz);
create table if not exists public.print_jobs(id uuid primary key default gen_random_uuid(),branch_id uuid not null references public.branches(id) on delete cascade,order_id uuid references public.orders(id) on delete cascade,job_type text not null default 'KOT',printer_name text,status text not null default 'Queued',error text,created_by uuid,created_at timestamptz default now(),printed_at timestamptz);
alter table public.kitchen_departments enable row level security;alter table public.printer_settings enable row level security;alter table public.kitchen_tickets enable row level security;alter table public.print_jobs enable row level security;
do $$ begin create policy "p4 departments branch" on public.kitchen_departments for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p4 printers branch" on public.printer_settings for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p4 tickets branch" on public.kitchen_tickets for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p4 printjobs branch" on public.print_jobs for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p4 orderitems update" on public.order_items for update to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())) with check(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.kitchen_tickets; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.print_jobs; exception when duplicate_object then null; end $$;


-- ===== SOURCE: 006_phase5_delivery_tables_shifts.sql =====
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


-- ===== SOURCE: 007_phase6_inventory_purchasing.sql =====
-- NEXA Phase 6: Inventory, recipes, purchasing, wastage, transfers and closing counts
create extension if not exists pgcrypto;
create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$ select u.branch_id from public.users u where u.auth_id=auth.uid() limit 1 $$;
grant execute on function public.nexa_my_branch() to authenticated;

create table if not exists public.inventory_categories(id uuid primary key default gen_random_uuid(),branch_id uuid not null,name text not null,active boolean default true,created_at timestamptz default now(),unique(branch_id,name));
create table if not exists public.inventory_ingredients(id uuid primary key default gen_random_uuid(),branch_id uuid not null default public.nexa_my_branch(),category_id uuid references public.inventory_categories(id) on delete set null,name text not null,unit text not null default 'PCS',current_stock numeric(14,3) not null default 0,min_stock numeric(14,3) not null default 0,avg_cost numeric(14,2) not null default 0,active boolean default true,created_at timestamptz default now(),updated_at timestamptz default now(),unique(branch_id,name));
create table if not exists public.inventory_recipes(id uuid primary key default gen_random_uuid(),branch_id uuid not null default public.nexa_my_branch(),product_id uuid,name text not null,yield_qty numeric(12,3) default 1,active boolean default true,created_at timestamptz default now());
create table if not exists public.inventory_recipe_items(id uuid primary key default gen_random_uuid(),recipe_id uuid not null references public.inventory_recipes(id) on delete cascade,ingredient_id uuid not null references public.inventory_ingredients(id),quantity numeric(14,3) not null check(quantity>0),unique(recipe_id,ingredient_id));
create table if not exists public.suppliers(id uuid primary key default gen_random_uuid(),branch_id uuid not null default public.nexa_my_branch(),name text not null,phone text,email text,address text,opening_balance numeric(14,2) default 0,active boolean default true,created_at timestamptz default now());
create table if not exists public.inventory_purchases(id uuid primary key default gen_random_uuid(),branch_id uuid not null default public.nexa_my_branch(),supplier_id uuid references public.suppliers(id),reference text,status text not null default 'RECEIVED',subtotal numeric(14,2) default 0,total numeric(14,2) default 0,created_by uuid default auth.uid(),created_at timestamptz default now());
create table if not exists public.inventory_purchase_items(id uuid primary key default gen_random_uuid(),purchase_id uuid not null references public.inventory_purchases(id) on delete cascade,ingredient_id uuid not null references public.inventory_ingredients(id),quantity numeric(14,3) not null check(quantity>0),unit_cost numeric(14,2) not null default 0,total numeric(14,2) generated always as (quantity*unit_cost) stored);
create table if not exists public.inventory_movements(id uuid primary key default gen_random_uuid(),branch_id uuid not null,movement_type text not null check(movement_type in('PURCHASE','CONSUMPTION','WASTAGE','TRANSFER_OUT','TRANSFER_IN','ADJUSTMENT','CLOSING')),ingredient_id uuid not null references public.inventory_ingredients(id),quantity numeric(14,3) not null,balance_after numeric(14,3) not null,unit_cost numeric(14,2) default 0,reference_type text,reference_id uuid,notes text,created_by uuid default auth.uid(),created_at timestamptz default now());
create table if not exists public.inventory_wastage(id uuid primary key default gen_random_uuid(),branch_id uuid not null default public.nexa_my_branch(),ingredient_id uuid not null references public.inventory_ingredients(id),quantity numeric(14,3) not null check(quantity>0),reason text,created_by uuid default auth.uid(),created_at timestamptz default now());
create table if not exists public.inventory_transfers(id uuid primary key default gen_random_uuid(),from_branch_id uuid not null,to_branch_id uuid not null,ingredient_id uuid not null references public.inventory_ingredients(id),quantity numeric(14,3) not null check(quantity>0),status text not null default 'SENT',notes text,created_by uuid default auth.uid(),created_at timestamptz default now());
create table if not exists public.inventory_closings(id uuid primary key default gen_random_uuid(),branch_id uuid not null default public.nexa_my_branch(),notes text,created_by uuid default auth.uid(),created_at timestamptz default now());
create table if not exists public.inventory_closing_items(id uuid primary key default gen_random_uuid(),closing_id uuid not null references public.inventory_closings(id) on delete cascade,ingredient_id uuid not null references public.inventory_ingredients(id),system_qty numeric(14,3) not null,counted_qty numeric(14,3) not null,variance numeric(14,3) generated always as (counted_qty-system_qty) stored);

create or replace function public.nexa_receive_purchase(p_supplier_id uuid,p_reference text,p_items jsonb) returns uuid language plpgsql security definer set search_path=public as $$ declare v_branch uuid:=public.nexa_my_branch();v_id uuid;v jsonb;v_ing public.inventory_ingredients%rowtype;v_qty numeric;v_cost numeric;v_total numeric:=0; begin if v_branch is null then raise exception 'No branch assigned'; end if; insert into inventory_purchases(branch_id,supplier_id,reference) values(v_branch,p_supplier_id,p_reference) returning id into v_id; for v in select * from jsonb_array_elements(p_items) loop v_qty:=(v->>'qty')::numeric;v_cost:=coalesce((v->>'unit_cost')::numeric,0); select * into v_ing from inventory_ingredients where id=(v->>'ingredient_id')::uuid and branch_id=v_branch for update; if not found then raise exception 'Ingredient not found for branch'; end if; insert into inventory_purchase_items(purchase_id,ingredient_id,quantity,unit_cost) values(v_id,v_ing.id,v_qty,v_cost); update inventory_ingredients set current_stock=current_stock+v_qty,avg_cost=case when current_stock+v_qty=0 then avg_cost else ((current_stock*avg_cost)+(v_qty*v_cost))/(current_stock+v_qty) end,updated_at=now() where id=v_ing.id returning * into v_ing; insert into inventory_movements(branch_id,movement_type,ingredient_id,quantity,balance_after,unit_cost,reference_type,reference_id) values(v_branch,'PURCHASE',v_ing.id,v_qty,v_ing.current_stock,v_cost,'PURCHASE',v_id);v_total:=v_total+(v_qty*v_cost); end loop; update inventory_purchases set subtotal=v_total,total=v_total where id=v_id;return v_id; end $$;
create or replace function public.nexa_record_wastage(p_ingredient_id uuid,p_qty numeric,p_reason text) returns uuid language plpgsql security definer set search_path=public as $$ declare v_branch uuid:=public.nexa_my_branch();v_id uuid;v_balance numeric;begin if p_qty<=0 then raise exception 'Quantity must be positive';end if; update inventory_ingredients set current_stock=current_stock-p_qty,updated_at=now() where id=p_ingredient_id and branch_id=v_branch and current_stock>=p_qty returning current_stock into v_balance;if v_balance is null then raise exception 'Insufficient stock';end if;insert into inventory_wastage(branch_id,ingredient_id,quantity,reason) values(v_branch,p_ingredient_id,p_qty,p_reason) returning id into v_id;insert into inventory_movements(branch_id,movement_type,ingredient_id,quantity,balance_after,reference_type,reference_id,notes) values(v_branch,'WASTAGE',p_ingredient_id,-p_qty,v_balance,'WASTAGE',v_id,p_reason);return v_id;end $$;
create or replace function public.nexa_save_inventory_closing(p_items jsonb,p_notes text) returns uuid language plpgsql security definer set search_path=public as $$ declare v_branch uuid:=public.nexa_my_branch();v_id uuid;v jsonb;v_old numeric;v_new numeric;begin insert into inventory_closings(branch_id,notes) values(v_branch,p_notes) returning id into v_id;for v in select * from jsonb_array_elements(p_items) loop v_old:=(v->>'system_qty')::numeric;v_new:=(v->>'counted_qty')::numeric;insert into inventory_closing_items(closing_id,ingredient_id,system_qty,counted_qty) values(v_id,(v->>'ingredient_id')::uuid,v_old,v_new);update inventory_ingredients set current_stock=v_new,updated_at=now() where id=(v->>'ingredient_id')::uuid and branch_id=v_branch;insert into inventory_movements(branch_id,movement_type,ingredient_id,quantity,balance_after,reference_type,reference_id,notes) values(v_branch,'CLOSING',(v->>'ingredient_id')::uuid,v_new-v_old,v_new,'CLOSING',v_id,p_notes);end loop;return v_id;end $$;
grant execute on function public.nexa_receive_purchase(uuid,text,jsonb),public.nexa_record_wastage(uuid,numeric,text),public.nexa_save_inventory_closing(jsonb,text) to authenticated;

-- Optional product-to-recipe consumption. Safe to call from POS after an order is confirmed.
create or replace function public.nexa_consume_recipe(p_product_id uuid,p_qty numeric,p_reference_id uuid default null) returns void language plpgsql security definer set search_path=public as $$ declare v_branch uuid:=public.nexa_my_branch();r record;v_balance numeric;begin for r in select ri.ingredient_id,ri.quantity from inventory_recipes rr join inventory_recipe_items ri on ri.recipe_id=rr.id where rr.branch_id=v_branch and rr.product_id=p_product_id and rr.active loop update inventory_ingredients set current_stock=current_stock-(r.quantity*p_qty),updated_at=now() where id=r.ingredient_id and branch_id=v_branch and current_stock>=r.quantity*p_qty returning current_stock into v_balance;if v_balance is null then raise exception 'Insufficient ingredient stock';end if;insert into inventory_movements(branch_id,movement_type,ingredient_id,quantity,balance_after,reference_type,reference_id) values(v_branch,'CONSUMPTION',r.ingredient_id,-(r.quantity*p_qty),v_balance,'ORDER',p_reference_id);end loop;end $$;
grant execute on function public.nexa_consume_recipe(uuid,numeric,uuid) to authenticated;

-- RLS: branch scoped inventory. Transfers allow source/destination visibility.
do $$ declare t text; begin foreach t in array array['inventory_categories','inventory_ingredients','inventory_recipes','suppliers','inventory_purchases','inventory_movements','inventory_wastage','inventory_closings'] loop execute format('alter table public.%I enable row level security',t); execute format('drop policy if exists %I on public.%I','p6_branch_'||t,t); execute format('create policy %I on public.%I for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch())','p6_branch_'||t,t); end loop; end $$;
alter table public.inventory_transfers enable row level security;drop policy if exists p6_transfers on public.inventory_transfers;create policy p6_transfers on public.inventory_transfers for all to authenticated using(from_branch_id=public.nexa_my_branch() or to_branch_id=public.nexa_my_branch()) with check(from_branch_id=public.nexa_my_branch());
-- Child rows are protected through their parents.
alter table public.inventory_recipe_items enable row level security;drop policy if exists p6_recipe_items on public.inventory_recipe_items;create policy p6_recipe_items on public.inventory_recipe_items for all to authenticated using(exists(select 1 from inventory_recipes r where r.id=recipe_id and r.branch_id=public.nexa_my_branch())) with check(exists(select 1 from inventory_recipes r where r.id=recipe_id and r.branch_id=public.nexa_my_branch()));
alter table public.inventory_purchase_items enable row level security;drop policy if exists p6_purchase_items on public.inventory_purchase_items;create policy p6_purchase_items on public.inventory_purchase_items for all to authenticated using(exists(select 1 from inventory_purchases p where p.id=purchase_id and p.branch_id=public.nexa_my_branch())) with check(exists(select 1 from inventory_purchases p where p.id=purchase_id and p.branch_id=public.nexa_my_branch()));
alter table public.inventory_closing_items enable row level security;drop policy if exists p6_closing_items on public.inventory_closing_items;create policy p6_closing_items on public.inventory_closing_items for all to authenticated using(exists(select 1 from inventory_closings c where c.id=closing_id and c.branch_id=public.nexa_my_branch())) with check(exists(select 1 from inventory_closings c where c.id=closing_id and c.branch_id=public.nexa_my_branch()));


-- ===== SOURCE: 008_phase7_accounting_reports.sql =====
-- NEXA Phase 7: Accounting + Reports (schema-compatible with the core NEXA tables)
-- Depends on migrations 001-006. Uses stock_movements + ingredients, not legacy inventory_movements.
create extension if not exists pgcrypto;

create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$
  select branch_id from public.users where auth_id=auth.uid() limit 1
$$;
grant execute on function public.nexa_my_branch() to authenticated;

create index if not exists idx_orders_branch_created on public.orders(branch_id,created_at);
create index if not exists idx_orders_branch_completed on public.orders(branch_id,completed_at);
create index if not exists idx_payments_created on public.payments(created_at);
create index if not exists idx_expenses_branch_created on public.expenses(branch_id,created_at);
create index if not exists idx_shifts_branch_opened on public.shifts(branch_id,opened_at);
create index if not exists idx_stock_mov_branch_created on public.stock_movements(branch_id,created_at);

create or replace function public.nexa_finance_dashboard(p_start date,p_end date)
returns table(gross_sales numeric,discounts numeric,tax numeric,net_sales numeric,orders bigint,collected numeric,due_amount numeric,expenses numeric,purchases numeric,cogs numeric,wastage numeric,gross_profit numeric,gross_margin numeric,net_profit numeric)
language sql stable security definer set search_path=public as $$
with o as (
 select coalesce(sum(total),0) gross_sales,coalesce(sum(discount),0) discounts,coalesce(sum(tax),0) tax,coalesce(sum(grand_total),0) net_sales,count(*) orders
 from orders where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), p as (
 select coalesce(sum(case when p.reversed_at is null and lower(coalesce(p.status,'')) not in ('reversed','cancelled') then p.amount else 0 end),0) collected
 from payments p join orders o2 on o2.id=p.order_id where o2.branch_id=nexa_my_branch() and p.created_at>=p_start::timestamptz and p.created_at<(p_end+1)::timestamptz
), e as (
 select coalesce(sum(amount),0) expenses from expenses where branch_id=nexa_my_branch() and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), pu as (
 select coalesce(sum(total),0) purchases from purchases where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','rejected') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), c as (
 select
   coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('sale','consumption','recipe_consumption','order_consumption','stock_out')),0) cogs,
   coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('wastage','waste')),0) wastage
 from stock_movements sm left join ingredients i on i.id=sm.ingredient_id
 where sm.branch_id=nexa_my_branch() and sm.created_at>=p_start::timestamptz and sm.created_at<(p_end+1)::timestamptz
)
select o.gross_sales,o.discounts,o.tax,o.net_sales,o.orders,p.collected,greatest(o.net_sales-p.collected,0),e.expenses,pu.purchases,c.cogs,c.wastage,
(o.net_sales-o.tax-c.cogs),case when o.net_sales-o.tax=0 then 0 else ((o.net_sales-o.tax-c.cogs)/(o.net_sales-o.tax))*100 end,
(o.net_sales-o.tax-c.cogs-e.expenses-c.wastage) from o,p,e,pu,c;
$$;

create or replace function public.nexa_daily_sales(p_start date,p_end date)
returns table(sale_date date,orders bigint,gross_sales numeric,discounts numeric,tax numeric,net_sales numeric,avg_bill numeric)
language sql stable security definer set search_path=public as $$
 select (created_at at time zone 'Asia/Karachi')::date,count(*),coalesce(sum(total),0),coalesce(sum(discount),0),coalesce(sum(tax),0),coalesce(sum(grand_total),0),coalesce(avg(grand_total),0)
 from orders where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz group by 1 order by 1;
$$;

create or replace function public.nexa_payment_summary(p_start date,p_end date)
returns table(method text,transactions bigint,collected numeric,reversed numeric,net_collection numeric)
language sql stable security definer set search_path=public as $$
 select p.method,count(*),coalesce(sum(case when p.reversed_at is null then p.amount else 0 end),0),coalesce(sum(case when p.reversed_at is not null then p.amount else 0 end),0),coalesce(sum(case when p.reversed_at is null then p.amount else -p.amount end),0)
 from payments p join orders o on o.id=p.order_id where o.branch_id=nexa_my_branch() and p.created_at>=p_start::timestamptz and p.created_at<(p_end+1)::timestamptz group by p.method order by 5 desc;
$$;

create or replace function public.nexa_expense_summary(p_start date,p_end date)
returns table(category text,entries bigint,amount numeric)
language sql stable security definer set search_path=public as $$
 select coalesce(nullif(e.category,''),'Uncategorized'),count(*),coalesce(sum(e.amount),0) from expenses e
 where e.branch_id=nexa_my_branch() and e.created_at>=p_start::timestamptz and e.created_at<(p_end+1)::timestamptz group by 1 order by 3 desc;
$$;

create or replace function public.nexa_profit_loss(p_start date,p_end date)
returns table(metric text,amount numeric)
language sql stable security definer set search_path=public as $$
 with d as (select * from nexa_finance_dashboard(p_start,p_end))
 select 'Net Sales',net_sales from d union all select 'Less: Tax / VAT',-tax from d union all select 'Less: Cost of Goods Sold',-cogs from d union all select 'Gross Profit',gross_profit from d union all select 'Less: Operating Expenses',-expenses from d union all select 'Less: Wastage',-wastage from d union all select 'Estimated Net Profit',net_profit from d;
$$;

create or replace function public.nexa_tax_summary(p_start date,p_end date)
returns table(sale_date date,taxable_sales numeric,tax_collected numeric,orders bigint)
language sql stable security definer set search_path=public as $$
 select (created_at at time zone 'Asia/Karachi')::date,coalesce(sum(grand_total-tax),0),coalesce(sum(tax),0),count(*) from orders
 where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz group by 1 order by 1;
$$;

create or replace function public.nexa_shift_summary(p_start date,p_end date)
returns table(opened_at timestamptz,closed_at timestamptz,status text,opening_cash numeric,cash_sales numeric,expenses numeric,expected_cash numeric,closing_cash numeric,difference numeric)
language sql stable security definer set search_path=public as $$
 select s.opened_at,s.closed_at,s.status,s.opening_cash,
 coalesce((select sum(p.amount) from payments p join orders o on o.id=p.order_id where o.shift_id=s.id and lower(p.method)='cash' and p.reversed_at is null),0),
 coalesce((select sum(e.amount) from expenses e where e.shift_id=s.id),0),coalesce(s.expected_cash,0),coalesce(s.actual_cash,0),coalesce(s.actual_cash,0)-coalesce(s.expected_cash,0)
 from shifts s where s.branch_id=nexa_my_branch() and s.opened_at>=p_start::timestamptz and s.opened_at<(p_end+1)::timestamptz order by s.opened_at desc;
$$;

grant execute on function public.nexa_finance_dashboard(date,date),public.nexa_daily_sales(date,date),public.nexa_payment_summary(date,date),public.nexa_expense_summary(date,date),public.nexa_profit_loss(date,date),public.nexa_tax_summary(date,date),public.nexa_shift_summary(date,date) to authenticated;

alter table public.payments replica identity full;
alter table public.expenses replica identity full;


-- ===== SOURCE: 009_phase8_security_production.sql =====
-- NEXA Phase 8: security, privileged actions, audit trail and production safeguards
-- Run after the corrected 008 migration.
create extension if not exists pgcrypto;

create or replace function public.nexa_my_user_id() returns uuid language sql stable security definer set search_path=public as $$
 select id from public.users where auth_id=auth.uid() limit 1
$$;
create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$
 select branch_id from public.users where auth_id=auth.uid() limit 1
$$;
create or replace function public.nexa_my_role() returns text language sql stable security definer set search_path=public as $$
 select coalesce((select r.name from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id limit 1),u.role,'Cashier') from public.users u where u.auth_id=auth.uid() limit 1
$$;
create or replace function public.nexa_is_management() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(public.nexa_my_role() in ('Developer','Admin','Manager'),false)
$$;
grant execute on function public.nexa_my_user_id(),public.nexa_my_branch(),public.nexa_my_role(),public.nexa_is_management() to authenticated;

-- Normalize the audit table regardless of which early schema created it first.
alter table public.audit_log add column if not exists actor_id uuid;
alter table public.audit_log add column if not exists metadata jsonb default '{}'::jsonb;
alter table public.manager_authorizations add column if not exists branch_id uuid;
alter table public.manager_authorizations add column if not exists requested_by uuid;
alter table public.manager_authorizations add column if not exists authorized_by uuid;
alter table public.manager_authorizations add column if not exists action text;
alter table public.manager_authorizations add column if not exists entity_type text;
alter table public.manager_authorizations add column if not exists entity_id uuid;
alter table public.manager_authorizations add column if not exists reason text;
alter table public.manager_authorizations add column if not exists created_at timestamptz default now();
alter table public.payments add column if not exists reversed_by uuid;

create or replace function public.nexa_authorize_manager_pin(p_pin text,p_action text,p_entity_type text default null,p_entity_id uuid default null,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_authorizer uuid; v_id uuid; v_branch uuid:=public.nexa_my_branch();
begin
 if coalesce(trim(p_pin),'')='' then raise exception 'Manager PIN is required'; end if;
 select u.id into v_authorizer from public.users u
 where u.branch_id=v_branch and coalesce(u.status,'Active')='Active' and coalesce(u.role,public.nexa_my_role()) in ('Developer','Admin','Manager')
   and u.pin_hash is not null and crypt(p_pin,u.pin_hash)=u.pin_hash
 limit 1;
 if v_authorizer is null then raise exception 'Invalid manager authorization PIN'; end if;
 insert into public.manager_authorizations(branch_id,requested_by,authorized_by,action,entity_type,entity_id,reason)
 values(v_branch,public.nexa_my_user_id(),v_authorizer,p_action,p_entity_type,p_entity_id,p_reason) returning id into v_id;
 return v_id;
end $$;
grant execute on function public.nexa_authorize_manager_pin(text,text,text,uuid,text) to authenticated;

create or replace function public.nexa_secure_cancel_order(p_order_id uuid,p_reason text,p_manager_pin text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_role text:=public.nexa_my_role();
begin
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Cancellation reason is required'; end if;
 select * into v_order from public.orders where id=p_order_id and branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Order not found'; end if;
 if lower(coalesce(v_order.status,''))='cancelled' then raise exception 'Order is already cancelled'; end if;
 if v_role not in ('Developer','Admin','Manager') then perform public.nexa_authorize_manager_pin(p_manager_pin,'ORDER_CANCEL','order',p_order_id,p_reason); end if;
 update public.orders set status='Cancelled',cancel_reason=p_reason,updated_at=now() where id=p_order_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_order.branch_id,public.nexa_my_user_id(),'ORDER_CANCELLED','order',p_order_id,p_reason,jsonb_build_object('previous_status',v_order.status,'grand_total',v_order.grand_total));
end $$;
grant execute on function public.nexa_secure_cancel_order(uuid,text,text) to authenticated;

create or replace function public.nexa_reverse_payment(p_payment_id uuid,p_reason text,p_manager_pin text)
returns void language plpgsql security definer set search_path=public as $$
declare v_payment public.payments%rowtype; v_order public.orders%rowtype;
begin
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reversal reason is required'; end if;
 select p.* into v_payment from public.payments p join public.orders o on o.id=p.order_id where p.id=p_payment_id and o.branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Payment not found'; end if;
 if v_payment.reversed_at is not null then raise exception 'Payment is already reversed'; end if;
 perform public.nexa_authorize_manager_pin(p_manager_pin,'PAYMENT_REVERSE','payment',p_payment_id,p_reason);
 update public.payments set reversed_at=now(),reversal_reason=p_reason,reversed_by=public.nexa_my_user_id(),status='Reversed' where id=p_payment_id;
 select * into v_order from public.orders where id=v_payment.order_id;
 update public.orders set status='Placed',completed_at=null,updated_at=now() where id=v_payment.order_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_order.branch_id,public.nexa_my_user_id(),'PAYMENT_REVERSED','payment',p_payment_id,p_reason,jsonb_build_object('order_id',v_payment.order_id,'amount',v_payment.amount,'method',v_payment.method));
end $$;
grant execute on function public.nexa_reverse_payment(uuid,text,text) to authenticated;

create or replace function public.nexa_secure_close_shift(p_shift_id uuid,p_actual_cash numeric,p_manager_pin text,p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_shift public.shifts%rowtype; v_pending bigint; v_cash numeric:=0; v_in numeric:=0; v_out numeric:=0; v_exp numeric:=0; v_expected numeric:=0;
begin
 select * into v_shift from public.shifts where id=p_shift_id and branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Shift not found'; end if;
 if lower(coalesce(v_shift.status,''))='closed' then raise exception 'Shift is already closed'; end if;
 perform public.nexa_authorize_manager_pin(p_manager_pin,'SHIFT_CLOSE','shift',p_shift_id,p_note);
 select count(*) into v_pending from public.orders where shift_id=p_shift_id and lower(coalesce(status,'')) not in ('completed','cancelled');
 if v_pending>0 then raise exception 'Cannot close shift: % pending order(s) remain',v_pending; end if;
 select coalesce(sum(p.amount),0) into v_cash from public.payments p join public.orders o on o.id=p.order_id where o.shift_id=p_shift_id and lower(p.method)='cash' and p.reversed_at is null;
 select coalesce(sum(amount),0) into v_in from public.cash_movements where shift_id=p_shift_id and lower(type) in ('cash_in','in');
 select coalesce(sum(amount),0) into v_out from public.cash_movements where shift_id=p_shift_id and lower(type) in ('cash_out','out');
 select coalesce(sum(amount),0) into v_exp from public.expenses where shift_id=p_shift_id;
 v_expected:=coalesce(v_shift.opening_cash,0)+v_cash+v_in-v_out-v_exp;
 update public.shifts set status='Closed',closed_at=now(),closed_by=auth.uid(),expected_cash=v_expected,actual_cash=p_actual_cash where id=p_shift_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_shift.branch_id,public.nexa_my_user_id(),'SHIFT_CLOSED','shift',p_shift_id,p_note,jsonb_build_object('expected_cash',v_expected,'actual_cash',p_actual_cash,'difference',p_actual_cash-v_expected));
end $$;
grant execute on function public.nexa_secure_close_shift(uuid,numeric,text,text) to authenticated;

-- Remove the permissive Phase 2 policies from sensitive tables.
do $$ declare t text; begin
 foreach t in array array['manager_authorizations','shifts','cash_movements','expenses','audit_log'] loop
   if to_regclass('public.'||t) is not null then
     execute format('alter table public.%I enable row level security',t);
     execute format('drop policy if exists authenticated_all on public.%I',t);
   end if;
 end loop;
end $$;

-- Branch-scoped read/write policies. Privileged mutations should use the RPCs above.
drop policy if exists p8_shifts_read on public.shifts;
create policy p8_shifts_read on public.shifts for select to authenticated using(branch_id=public.nexa_my_branch());
drop policy if exists p8_shifts_insert on public.shifts;
create policy p8_shifts_insert on public.shifts for insert to authenticated with check(branch_id=public.nexa_my_branch() and public.nexa_is_management());
drop policy if exists p8_cash_branch on public.cash_movements;
create policy p8_cash_branch on public.cash_movements for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch());
drop policy if exists p8_expenses_branch on public.expenses;
create policy p8_expenses_branch on public.expenses for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch());
drop policy if exists p8_audit_read on public.audit_log;
create policy p8_audit_read on public.audit_log for select to authenticated using(branch_id=public.nexa_my_branch() and public.nexa_is_management());
drop policy if exists p8_auth_read on public.manager_authorizations;
create policy p8_auth_read on public.manager_authorizations for select to authenticated using(branch_id=public.nexa_my_branch() and public.nexa_is_management());

-- Prevent negative ingredient stock even when a client attempts a direct update.
create or replace function public.nexa_prevent_negative_stock() returns trigger language plpgsql as $$ begin
 if new.quantity<0 then raise exception 'Negative stock is not allowed for %',new.name; end if; return new; end $$;
drop trigger if exists trg_nexa_no_negative_stock on public.ingredients;
create trigger trg_nexa_no_negative_stock before insert or update of quantity on public.ingredients for each row execute function public.nexa_prevent_negative_stock();

create index if not exists idx_audit_branch_created on public.audit_log(branch_id,created_at desc);
create index if not exists idx_manager_auth_branch_created on public.manager_authorizations(branch_id,created_at desc);


-- ===== SOURCE: 010_phase9_role_access_admin_reverse.sql =====
-- NEXA Phase 9: restaurant role model + Admin-only paid -> unpaid reversal
insert into public.roles(name) values
 ('Admin'),('Manager'),('Cashier'),('Call Center'),('Dispatcher'),('Delivery Boy'),('Order Taker')
on conflict(name) do nothing;

-- Keep older names compatible with existing accounts while new users use the names above.
create or replace function public.nexa_my_role() returns text language sql stable security definer set search_path=public as $$
 select case lower(coalesce((select r.name from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id limit 1),u.role,'Cashier'))
   when 'rider' then 'Delivery Boy'
   when 'waiter' then 'Order Taker'
   when 'despature' then 'Dispatcher'
   when 'despatcher' then 'Dispatcher'
   else coalesce((select r.name from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id limit 1),u.role,'Cashier') end
 from public.users u where u.auth_id=auth.uid() limit 1
$$;

create or replace function public.nexa_is_management() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(public.nexa_my_role() in ('Admin','Manager'),false)
$$;

grant execute on function public.nexa_my_role(),public.nexa_is_management() to authenticated;

create or replace function public.nexa_admin_mark_order_unpaid(p_order_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_count integer:=0;
begin
 if public.nexa_my_role()<>'Admin' then raise exception 'Only Admin can reverse a paid order to unpaid'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reversal reason is required'; end if;
 select * into v_order from public.orders where id=p_order_id and branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Order not found'; end if;
 update public.payments set reversed_at=now(),reversal_reason=p_reason,reversed_by=public.nexa_my_user_id(),status='Reversed'
 where order_id=p_order_id and reversed_at is null and lower(coalesce(status,'paid'))<>'reversed';
 get diagnostics v_count = row_count;
 if v_count=0 then raise exception 'This order has no active paid payment to reverse'; end if;
 update public.orders set status='Placed',completed_at=null,updated_at=now() where id=p_order_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_order.branch_id,public.nexa_my_user_id(),'ORDER_MARKED_UNPAID','order',p_order_id,p_reason,jsonb_build_object('reversed_payments',v_count,'grand_total',v_order.grand_total));
end $$;
grant execute on function public.nexa_admin_mark_order_unpaid(uuid,text) to authenticated;

-- Enforce payment permission in the database, not only in React.
drop policy if exists "p3 payments insert" on public.payments;
create policy "p9 payments insert by role" on public.payments for insert to authenticated
with check(public.nexa_my_role() in ('Admin','Manager','Cashier','Call Center','Dispatcher') and exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch()));

-- Order entry is available to front-counter/order-entry roles. Delivery Boy cannot punch orders.
drop policy if exists "p3 orders insert" on public.orders;
drop policy if exists "branch orders insert" on public.orders;
create policy "p9 orders insert by role" on public.orders for insert to authenticated
with check(branch_id=public.nexa_my_branch() and public.nexa_my_role() in ('Admin','Manager','Cashier','Call Center','Dispatcher','Order Taker'));

-- Dispatcher/Admin/Manager only: rider assignment.
create or replace function public.nexa_assign_rider(p_delivery_id uuid,p_rider_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=public.nexa_my_branch();
begin
 if public.nexa_my_role() not in ('Admin','Manager','Dispatcher') then raise exception 'Your role cannot assign orders to riders'; end if;
 if not exists(select 1 from public.deliveries where id=p_delivery_id and branch_id=v_branch) then raise exception 'Delivery not found'; end if;
 if not exists(select 1 from public.riders where id=p_rider_id and branch_id=v_branch and on_duty=true) then raise exception 'Rider is not available'; end if;
 update public.deliveries set rider_id=p_rider_id,status='Assigned',assigned_at=now() where id=p_delivery_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,metadata)
 values(v_branch,public.nexa_my_user_id(),'RIDER_ASSIGNED','delivery',p_delivery_id,jsonb_build_object('rider_id',p_rider_id));
end $$;
grant execute on function public.nexa_assign_rider(uuid,uuid) to authenticated;

-- Profit is a server-side Admin-only value. Other roles receive nulls even if they call the RPC manually.
create or replace function public.nexa_finance_dashboard(p_start date,p_end date)
returns table(gross_sales numeric,discounts numeric,tax numeric,net_sales numeric,orders bigint,collected numeric,due_amount numeric,expenses numeric,purchases numeric,cogs numeric,wastage numeric,gross_profit numeric,gross_margin numeric,net_profit numeric)
language sql stable security definer set search_path=public as $$
with o as (
 select coalesce(sum(total),0) gross_sales,coalesce(sum(discount),0) discounts,coalesce(sum(tax),0) tax,coalesce(sum(grand_total),0) net_sales,count(*) orders
 from orders where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), p as (
 select coalesce(sum(case when p.reversed_at is null and lower(coalesce(p.status,'')) not in ('reversed','cancelled') then p.amount else 0 end),0) collected
 from payments p join orders o2 on o2.id=p.order_id where o2.branch_id=nexa_my_branch() and p.created_at>=p_start::timestamptz and p.created_at<(p_end+1)::timestamptz
), e as (select coalesce(sum(amount),0) expenses from expenses where branch_id=nexa_my_branch() and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz),
pu as (select coalesce(sum(total),0) purchases from purchases where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','rejected') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz),
c as (select coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('sale','consumption','recipe_consumption','order_consumption','stock_out')),0) cogs,coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('wastage','waste')),0) wastage from stock_movements sm left join ingredients i on i.id=sm.ingredient_id where sm.branch_id=nexa_my_branch() and sm.created_at>=p_start::timestamptz and sm.created_at<(p_end+1)::timestamptz)
select o.gross_sales,o.discounts,o.tax,o.net_sales,o.orders,p.collected,greatest(o.net_sales-p.collected,0),e.expenses,pu.purchases,
 case when nexa_my_role()='Admin' then c.cogs else null end,
 case when nexa_my_role()='Admin' then c.wastage else null end,
 case when nexa_my_role()='Admin' then (o.net_sales-o.tax-c.cogs) else null end,
 case when nexa_my_role()='Admin' then (case when o.net_sales-o.tax=0 then 0 else ((o.net_sales-o.tax-c.cogs)/(o.net_sales-o.tax))*100 end) else null end,
 case when nexa_my_role()='Admin' then (o.net_sales-o.tax-c.cogs-e.expenses-c.wastage) else null end
from o,p,e,pu,c;
$$;

create or replace function public.nexa_profit_loss(p_start date,p_end date)
returns table(metric text,amount numeric) language plpgsql stable security definer set search_path=public as $$
begin
 if public.nexa_my_role()<>'Admin' then raise exception 'Profit & Loss is available to Admin only'; end if;
 return query with d as (select * from nexa_finance_dashboard(p_start,p_end))
 select 'Net Sales'::text,net_sales from d union all select 'Less: Tax / VAT',-tax from d union all select 'Less: Cost of Goods Sold',-cogs from d union all select 'Gross Profit',gross_profit from d union all select 'Less: Operating Expenses',-expenses from d union all select 'Less: Wastage',-wastage from d union all select 'Estimated Net Profit',net_profit from d;
end $$;


-- ===== SOURCE: 011_phase10_mobile_riders_public_ordering.sql =====
-- NEXA Phase 10: rider mobile app, order-taker workflow and public ordering/tracking
create extension if not exists pgcrypto;
alter table public.branches add column if not exists latitude numeric(10,7);
alter table public.branches add column if not exists longitude numeric(10,7);
alter table public.branches add column if not exists delivery_radius_km numeric(8,2) default 8;
alter table public.orders add column if not exists public_tracking_code text unique;
create index if not exists orders_public_tracking_idx on public.orders(public_tracking_code);

create table if not exists public.rider_attendance(
 id uuid primary key default gen_random_uuid(), rider_id uuid not null references public.riders(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete cascade, started_at timestamptz not null default now(), ended_at timestamptz,
 start_lat numeric(10,7), start_lng numeric(10,7), end_lat numeric(10,7), end_lng numeric(10,7)
);
create table if not exists public.rider_locations(
 id bigint generated always as identity primary key, rider_id uuid not null references public.riders(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete cascade, latitude numeric(10,7) not null, longitude numeric(10,7) not null,
 accuracy_m numeric(10,2), recorded_at timestamptz not null default now()
);
create index if not exists rider_locations_latest_idx on public.rider_locations(rider_id,recorded_at desc);
alter table public.rider_attendance enable row level security; alter table public.rider_locations enable row level security;
do $$ begin create policy "p10 attendance branch" on public.rider_attendance for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p10 locations branch" on public.rider_locations for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.rider_locations; exception when duplicate_object then null; end $$;

create or replace function public.nexa_rider_start_shift(p_rider_id uuid,p_lat numeric,p_lng numeric) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_branch uuid; begin select branch_id into v_branch from riders where id=p_rider_id; if v_branch is null or v_branch<>nexa_my_branch() then raise exception 'Rider is not in your branch'; end if; if exists(select 1 from rider_attendance where rider_id=p_rider_id and ended_at is null) then raise exception 'Shift already active'; end if; insert into rider_attendance(rider_id,branch_id,start_lat,start_lng) values(p_rider_id,v_branch,p_lat,p_lng) returning id into v_id; update riders set on_duty=true,status='Available',checked_in_at=now() where id=p_rider_id; insert into rider_locations(rider_id,branch_id,latitude,longitude) values(p_rider_id,v_branch,p_lat,p_lng); return v_id; end $$;
create or replace function public.nexa_rider_end_shift(p_rider_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin if not exists(select 1 from riders where id=p_rider_id and branch_id=nexa_my_branch()) then raise exception 'Not allowed'; end if; update rider_attendance set ended_at=now() where rider_id=p_rider_id and ended_at is null; update riders set on_duty=false,status='Off Duty',checked_out_at=now() where id=p_rider_id; end $$;
grant execute on function public.nexa_rider_start_shift(uuid,numeric,numeric) to authenticated; grant execute on function public.nexa_rider_end_shift(uuid) to authenticated;

-- Safe public read APIs: expose only active branch/menu information needed by customers.
create or replace function public.nexa_public_branches() returns table(id uuid,name text,address text,phone text,latitude numeric,longitude numeric,delivery_radius_km numeric) language sql stable security definer set search_path=public as $$ select b.id,b.name,b.address,b.phone,b.latitude,b.longitude,b.delivery_radius_km from branches b where coalesce(b.active,true)=true order by b.name $$;
create or replace function public.nexa_public_menu(p_branch_id uuid) returns table(item_id uuid,variant_id uuid,name text,variant_name text,price numeric,category_name text) language sql stable security definer set search_path=public as $$ select i.id,v.id,i.name,v.name,v.price,c.name from menu_items i join menu_variants v on v.item_id=i.id left join categories c on c.id=i.category_id where i.branch_id=p_branch_id and coalesce(i.active,true)=true and coalesce(v.active,true)=true order by c.sort_order,c.name,i.name,v.price $$;
grant execute on function public.nexa_public_branches() to anon,authenticated; grant execute on function public.nexa_public_menu(uuid) to anon,authenticated;

create or replace function public.nexa_public_place_order(p_branch_id uuid,p_customer_name text,p_phone text,p_address text,p_items jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_customer uuid;v_order uuid;v_total numeric:=0;v_code text:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));r jsonb;v_price numeric;v_name text;v_item uuid; begin
 if coalesce(trim(p_customer_name),'')='' or coalesce(trim(p_phone),'')='' or coalesce(trim(p_address),'')='' then raise exception 'Name, phone and delivery address are required'; end if;
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'Cart is empty'; end if;
 insert into customers(branch_id,name,phone,address) values(p_branch_id,p_customer_name,p_phone,p_address) returning id into v_customer;
 for r in select * from jsonb_array_elements(p_items) loop select v.price,i.name,i.id into v_price,v_name,v_item from menu_variants v join menu_items i on i.id=v.item_id where v.id=(r->>'variant_id')::uuid and i.branch_id=p_branch_id and i.active=true; if v_price is null then raise exception 'Invalid menu item'; end if; v_total:=v_total+(v_price*greatest(1,(r->>'qty')::numeric)); end loop;
 insert into orders(branch_id,customer_id,order_type,status,kitchen_status,total,grand_total,public_tracking_code) values(p_branch_id,v_customer,'Delivery','Placed','Processing',v_total,v_total,v_code) returning id into v_order;
 for r in select * from jsonb_array_elements(p_items) loop select v.price,i.name,i.id into v_price,v_name,v_item from menu_variants v join menu_items i on i.id=v.item_id where v.id=(r->>'variant_id')::uuid; insert into order_items(order_id,item_id,variant_id,name,qty,unit_price,status) values(v_order,v_item,(r->>'variant_id')::uuid,v_name,greatest(1,(r->>'qty')::numeric),v_price,'Pending'); end loop;
 insert into deliveries(order_id,branch_id,customer_name,customer_phone,delivery_address,status) values(v_order,p_branch_id,p_customer_name,p_phone,p_address,'Awaiting Rider');
 return jsonb_build_object('order_id',v_order,'tracking_code',v_code,'status','Placed','grand_total',v_total);
end $$; grant execute on function public.nexa_public_place_order(uuid,text,text,text,jsonb) to anon,authenticated;

create or replace function public.nexa_public_track_order(p_code text,p_phone text) returns table(tracking_code text,token bigint,status text,kitchen_status text,delivery_status text,branch_name text,rider_name text,rider_lat numeric,rider_lng numeric,location_time timestamptz) language sql stable security definer set search_path=public as $$
 select o.public_tracking_code,o.token,o.status,o.kitchen_status,d.status,b.name,r.name,rl.latitude,rl.longitude,rl.recorded_at
 from orders o join customers c on c.id=o.customer_id join branches b on b.id=o.branch_id left join deliveries d on d.order_id=o.id left join riders r on r.id=d.rider_id left join lateral(select x.latitude,x.longitude,x.recorded_at from rider_locations x where x.rider_id=r.id order by x.recorded_at desc limit 1) rl on true
 where upper(o.public_tracking_code)=upper(trim(p_code)) and regexp_replace(c.phone,'\D','','g')=regexp_replace(p_phone,'\D','','g') limit 1 $$;
grant execute on function public.nexa_public_track_order(text,text) to anon,authenticated;


-- ===== SOURCE: 012_nexa_final_rebuild.sql =====
-- NEXA FINAL REBUILD LAYER
-- Adds production recipe-theoretical usage, inventory reconciliation, rider geofence attendance and live rider control.

alter table public.branches add column if not exists attendance_radius_m integer not null default 500;
alter table public.branches add column if not exists timezone text not null default 'Asia/Karachi';

-- Theoretical ingredient usage is separate from physical stock.
create table if not exists public.order_theoretical_usage(
 id uuid primary key default gen_random_uuid(),
 branch_id uuid not null references public.branches(id) on delete cascade,
 order_id uuid not null references public.orders(id) on delete cascade,
 ingredient_id uuid not null references public.inventory_ingredients(id) on delete restrict,
 quantity numeric(14,3) not null check(quantity>=0),
 unit text,
 created_at timestamptz not null default now(),
 unique(order_id,ingredient_id)
);
create index if not exists otu_branch_date_idx on public.order_theoretical_usage(branch_id,created_at desc);
create index if not exists otu_ingredient_idx on public.order_theoretical_usage(ingredient_id,created_at desc);
alter table public.order_theoretical_usage enable row level security;
do $$ begin create policy "final theoretical branch" on public.order_theoretical_usage for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;

create or replace function public.nexa_sync_order_theoretical_usage() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.status='Completed' and old.status is distinct from 'Completed' then
    insert into order_theoretical_usage(branch_id,order_id,ingredient_id,quantity,unit)
    select new.branch_id,new.id,ri.ingredient_id,sum(oi.qty*ri.quantity),ii.unit
    from order_items oi
    join inventory_recipes rr on rr.product_id=oi.item_id and rr.branch_id=new.branch_id and rr.active=true
    join inventory_recipe_items ri on ri.recipe_id=rr.id
    join inventory_ingredients ii on ii.id=ri.ingredient_id
    where oi.order_id=new.id
    group by ri.ingredient_id,ii.unit
    on conflict(order_id,ingredient_id) do update set quantity=excluded.quantity,unit=excluded.unit,created_at=now();
  elsif old.status='Completed' and new.status is distinct from 'Completed' then
    delete from order_theoretical_usage where order_id=new.id;
  end if;
  return new;
end $$;
drop trigger if exists trg_nexa_theoretical_usage on public.orders;
create trigger trg_nexa_theoretical_usage after update of status on public.orders for each row execute function public.nexa_sync_order_theoretical_usage();

-- Reconciliation: book stock is physical ledger quantity. Expected closing subtracts theoretical recipe usage since last closing.
create or replace function public.nexa_inventory_reconciliation(p_as_of timestamptz default now())
returns table(ingredient_id uuid,name text,unit text,book_stock numeric,theoretical_used numeric,expected_stock numeric,min_stock numeric,avg_cost numeric,variance_value_per_unit numeric)
language sql stable security definer set search_path=public as $$
with last_close as (
 select max(ic.created_at) as at from inventory_closings ic where ic.branch_id=nexa_my_branch() and ic.created_at<=p_as_of
), usage as (
 select u.ingredient_id,sum(u.quantity)::numeric used
 from order_theoretical_usage u,last_close lc
 where u.branch_id=nexa_my_branch() and u.created_at>coalesce(lc.at,date_trunc('day',p_as_of)) and u.created_at<=p_as_of
 group by u.ingredient_id
)
select i.id,i.name,i.unit,i.current_stock,coalesce(u.used,0),i.current_stock-coalesce(u.used,0),i.min_stock,i.avg_cost,i.avg_cost
from inventory_ingredients i left join usage u on u.ingredient_id=i.id
where i.branch_id=nexa_my_branch() and i.active=true order by i.name
$$;
grant execute on function public.nexa_inventory_reconciliation(timestamptz) to authenticated;

-- Accurate distance in meters for rider attendance.
create or replace function public.nexa_distance_m(lat1 numeric,lon1 numeric,lat2 numeric,lon2 numeric) returns numeric
language sql immutable as $$
 select 6371000 * 2 * asin(sqrt(power(sin(radians((lat2-lat1)/2)),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians((lon2-lon1)/2)),2)))
$$;

create or replace function public.nexa_rider_start_shift(p_rider_id uuid,p_lat numeric,p_lng numeric) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_branch uuid;v_blat numeric;v_blng numeric;v_radius integer;v_distance numeric;v_uid uuid:=auth.uid();begin
 select r.branch_id into v_branch from riders r where r.id=p_rider_id and r.profile_id=v_uid;
 if v_branch is null or v_branch<>nexa_my_branch() then raise exception 'Rider account is not linked to this branch'; end if;
 select latitude,longitude,attendance_radius_m into v_blat,v_blng,v_radius from branches where id=v_branch;
 if v_blat is null or v_blng is null then raise exception 'Restaurant attendance location is not configured'; end if;
 v_distance:=nexa_distance_m(p_lat,p_lng,v_blat,v_blng);
 if v_distance>coalesce(v_radius,500) then raise exception 'You are % m from the restaurant. Move within % m to mark attendance',round(v_distance),coalesce(v_radius,500); end if;
 if exists(select 1 from rider_attendance where rider_id=p_rider_id and ended_at is null) then raise exception 'Shift already active'; end if;
 insert into rider_attendance(rider_id,branch_id,start_lat,start_lng) values(p_rider_id,v_branch,p_lat,p_lng) returning id into v_id;
 update riders set on_duty=true,status='Available',checked_in_at=now() where id=p_rider_id;
 insert into rider_locations(rider_id,branch_id,latitude,longitude) values(p_rider_id,v_branch,p_lat,p_lng);
 return v_id;
end $$;

create or replace function public.nexa_live_riders()
returns table(rider_id uuid,name text,phone text,status text,on_duty boolean,latitude numeric,longitude numeric,accuracy_m numeric,recorded_at timestamptz,active_delivery_id uuid,order_id uuid,token bigint)
language sql stable security definer set search_path=public as $$
 select r.id,r.name,r.phone,r.status,r.on_duty,l.latitude,l.longitude,l.accuracy_m,l.recorded_at,d.id,d.order_id,o.token
 from riders r
 left join lateral(select rl.latitude,rl.longitude,rl.accuracy_m,rl.recorded_at from rider_locations rl where rl.rider_id=r.id order by rl.recorded_at desc limit 1) l on true
 left join lateral(select dx.id,dx.order_id from deliveries dx where dx.rider_id=r.id and dx.status not in('Delivered','Cancelled') order by dx.assigned_at desc nulls last limit 1) d on true
 left join orders o on o.id=d.order_id
 where r.branch_id=nexa_my_branch() order by r.on_duty desc,r.name
$$;
grant execute on function public.nexa_live_riders() to authenticated;

-- Branch location/settings helper for management.
create or replace function public.nexa_save_branch_geo(p_lat numeric,p_lng numeric,p_delivery_radius_km numeric default 8,p_attendance_radius_m integer default 500)
returns void language plpgsql security definer set search_path=public as $$
begin
 if nexa_my_role() not in('Admin','Manager') then raise exception 'Not allowed'; end if;
 update branches set latitude=p_lat,longitude=p_lng,delivery_radius_km=greatest(.5,p_delivery_radius_km),attendance_radius_m=greatest(50,least(5000,p_attendance_radius_m)) where id=nexa_my_branch();
end $$;
grant execute on function public.nexa_save_branch_geo(numeric,numeric,numeric,integer) to authenticated;

-- Helpful indexes
create index if not exists orders_branch_status_created_idx on public.orders(branch_id,status,created_at desc);
create index if not exists deliveries_branch_status_idx on public.deliveries(branch_id,status,assigned_at desc);
create index if not exists inventory_ing_branch_active_idx on public.inventory_ingredients(branch_id,active,name);

create or replace function public.nexa_save_recipe(p_product_id uuid,p_name text,p_yield_qty numeric,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=nexa_my_branch();v_id uuid;v jsonb;begin
 if nexa_my_role() not in('Admin','Manager') then raise exception 'Not allowed'; end if;
 if p_product_id is null or coalesce(trim(p_name),'')='' then raise exception 'Menu item and recipe name are required'; end if;
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'Add at least one ingredient'; end if;
 insert into inventory_recipes(branch_id,product_id,name,yield_qty,active) values(v_branch,p_product_id,p_name,greatest(p_yield_qty,0.001),true)
 returning id into v_id;
 for v in select * from jsonb_array_elements(p_items) loop
  insert into inventory_recipe_items(recipe_id,ingredient_id,quantity) values(v_id,(v->>'ingredient_id')::uuid,(v->>'quantity')::numeric);
 end loop;
 return v_id;
end $$;
grant execute on function public.nexa_save_recipe(uuid,text,numeric,jsonb) to authenticated;

-- One-time safe bootstrap after creating the first Auth user.
create or replace function public.nexa_bootstrap_first_admin(p_name text default 'NEXA Admin') returns void
language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();v_email text;begin
 if v_uid is null then raise exception 'Login first'; end if;
 if exists(select 1 from profiles where lower(role)='admin' and active=true) then raise exception 'An Admin already exists'; end if;
 select email into v_email from auth.users where id=v_uid;
 insert into profiles(id,name,email,role,active) values(v_uid,coalesce(nullif(trim(p_name),''),'NEXA Admin'),v_email,'Admin',true)
 on conflict(id) do update set name=excluded.name,email=excluded.email,role='Admin',active=true;
end $$;
grant execute on function public.nexa_bootstrap_first_admin(text) to authenticated;

-- NEXA v21: standard rider reading / distance ledger
alter table public.deliveries add column if not exists standard_one_way_km numeric(10,2);
alter table public.deliveries add column if not exists reading_km numeric(10,2);
alter table public.deliveries add column if not exists reading_credited_at timestamptz;

create table if not exists public.rider_reading_ledger(
 id uuid primary key default gen_random_uuid(),
 branch_id uuid not null references public.branches(id) on delete cascade,
 rider_id uuid not null references public.riders(id) on delete cascade,
 delivery_id uuid not null references public.deliveries(id) on delete cascade,
 order_id uuid not null references public.orders(id) on delete cascade,
 one_way_km numeric(10,2) not null check(one_way_km>=0),
 credited_km numeric(10,2) not null check(credited_km>=0),
 calculation text not null default 'round_trip_standard',
 reason text,
 created_by uuid references public.profiles(id),
 created_at timestamptz not null default now(),
 unique(delivery_id)
);
create index if not exists idx_rider_reading_rider_date on public.rider_reading_ledger(rider_id,created_at desc);
create index if not exists idx_rider_reading_branch_date on public.rider_reading_ledger(branch_id,created_at desc);
alter table public.rider_reading_ledger enable row level security;
do $$ begin create policy "rider reading branch view" on public.rider_reading_ledger for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;

create or replace function public.nexa_set_delivery_standard_distance(p_delivery_id uuid,p_one_way_km numeric,p_reason text default null)
returns public.deliveries language plpgsql security definer set search_path=public as $$
declare v public.deliveries;begin
 if public.nexa_my_role() not in('Admin','Manager') then raise exception 'Only Admin or Manager can set standard delivery distance'; end if;
 if p_one_way_km is null or p_one_way_km<0 or p_one_way_km>500 then raise exception 'Invalid one-way distance'; end if;
 update public.deliveries set standard_one_way_km=round(p_one_way_km,2),reading_km=round(p_one_way_km*2,2)
 where id=p_delivery_id and branch_id=public.nexa_my_branch() returning * into v;
 if v.id is null then raise exception 'Delivery not found'; end if;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v.branch_id,auth.uid(),'DELIVERY_DISTANCE_SET','delivery',v.id,p_reason,jsonb_build_object('one_way_km',p_one_way_km,'round_trip_reading_km',p_one_way_km*2));
 return v;
end$$;
grant execute on function public.nexa_set_delivery_standard_distance(uuid,numeric,text) to authenticated;

create or replace function public.nexa_credit_rider_reading() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if lower(coalesce(new.status,''))='delivered' and lower(coalesce(old.status,''))<>'delivered' and new.rider_id is not null and coalesce(new.standard_one_way_km,0)>0 then
   insert into public.rider_reading_ledger(branch_id,rider_id,delivery_id,order_id,one_way_km,credited_km,calculation,created_by)
   values(new.branch_id,new.rider_id,new.id,new.order_id,new.standard_one_way_km,new.standard_one_way_km*2,'round_trip_standard',auth.uid())
   on conflict(delivery_id) do nothing;
   new.reading_km:=new.standard_one_way_km*2; new.reading_credited_at:=coalesce(new.reading_credited_at,now());
 end if;
 return new;
end$$;
drop trigger if exists trg_nexa_credit_rider_reading on public.deliveries;
create trigger trg_nexa_credit_rider_reading before update of status on public.deliveries for each row execute function public.nexa_credit_rider_reading();

create or replace function public.nexa_rider_reading_summary(p_from timestamptz default date_trunc('day',now()),p_to timestamptz default now())
returns table(rider_id uuid,rider_name text,deliveries bigint,total_reading_km numeric) language sql stable security definer set search_path=public as $$
 select rr.rider_id,r.name,count(*),coalesce(sum(rr.credited_km),0)
 from rider_reading_ledger rr join riders r on r.id=rr.rider_id
 where rr.branch_id=nexa_my_branch() and rr.created_at>=p_from and rr.created_at<=p_to
 group by rr.rider_id,r.name order by sum(rr.credited_km) desc
$$;
grant execute on function public.nexa_rider_reading_summary(timestamptz,timestamptz) to authenticated;
-- Customer-site menu imagery. Staff POS intentionally remains text-first.
alter table public.menu_items add column if not exists image_url text;
create or replace function public.nexa_public_menu(p_branch_id uuid)
returns table(item_id uuid,variant_id uuid,name text,variant_name text,price numeric,category_name text,image_url text)
language sql stable security definer set search_path=public as $$
 select i.id,v.id,i.name,v.name,v.price,c.name,i.image_url
 from menu_items i join menu_variants v on v.item_id=i.id left join categories c on c.id=i.category_id
 where i.branch_id=p_branch_id and coalesce(i.active,true)=true and coalesce(v.active,true)=true
 order by c.sort_order,c.name,i.name,v.price
$$;
grant execute on function public.nexa_public_menu(uuid) to anon,authenticated;
