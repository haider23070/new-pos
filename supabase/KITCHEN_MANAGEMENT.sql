-- NEXA Kitchen Management migration
create extension if not exists pgcrypto;

alter table public.pos_products add column if not exists sku text;
alter table public.pos_products add column if not exists not_for_sale boolean not null default false;
alter table public.pos_products add column if not exists order_types text[] not null default array['Dine-In','Take-Away','Delivery','Third Party','Car Service'];
alter table public.pos_products add column if not exists sort_order integer not null default 0;

alter table public.pos_product_variants add column if not exists is_default boolean not null default false;
alter table public.pos_product_variants add column if not exists sort_order integer not null default 0;

create table if not exists public.pos_food_departments (
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade,
 name text not null, active boolean not null default true, created_at timestamptz not null default now(), unique(branch_id,name)
);
alter table public.pos_categories add column if not exists department_id uuid references public.pos_food_departments(id) on delete set null;
alter table public.pos_categories add column if not exists tax_rate numeric(6,2) not null default 0;

create table if not exists public.pos_branch_printers (
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade,
 name text not null, department_id uuid references public.pos_food_departments(id) on delete cascade,
 printer_name text not null, active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.pos_food_addons (
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade,
 name text not null, price numeric(12,2) not null default 0, active boolean not null default true, created_at timestamptz not null default now()
);
create table if not exists public.pos_order_notes (
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade,
 name text not null, active boolean not null default true, created_at timestamptz not null default now()
);

alter table public.pos_food_departments enable row level security;
alter table public.pos_branch_printers enable row level security;
alter table public.pos_food_addons enable row level security;
alter table public.pos_order_notes enable row level security;

do $pol$ begin
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='pos_food_departments' and policyname='kitchen_authenticated') then create policy kitchen_authenticated on public.pos_food_departments for all to authenticated using(true) with check(true); end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='pos_branch_printers' and policyname='kitchen_authenticated') then create policy kitchen_authenticated on public.pos_branch_printers for all to authenticated using(true) with check(true); end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='pos_food_addons' and policyname='kitchen_authenticated') then create policy kitchen_authenticated on public.pos_food_addons for all to authenticated using(true) with check(true); end if;
 if not exists(select 1 from pg_policies where schemaname='public' and tablename='pos_order_notes' and policyname='kitchen_authenticated') then create policy kitchen_authenticated on public.pos_order_notes for all to authenticated using(true) with check(true); end if;
end $pol$;

grant select,insert,update,delete on public.pos_food_departments,public.pos_branch_printers,public.pos_food_addons,public.pos_order_notes to authenticated;
notify pgrst, 'reload schema';
