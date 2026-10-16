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
