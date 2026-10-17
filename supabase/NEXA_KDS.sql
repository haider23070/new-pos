-- NEXA Kitchen Display System
-- Run once in Supabase SQL Editor.
create table if not exists public.pos_kds_item_status (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.pos_branches(id) on delete cascade,
  order_id uuid not null references public.pos_orders(id) on delete cascade,
  order_item_id uuid not null references public.pos_order_items(id) on delete cascade,
  status text not null default 'Pending' check (status in ('Pending','Processing','Prepared','Served')),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  unique(order_item_id)
);
create index if not exists pos_kds_item_status_branch_idx on public.pos_kds_item_status(branch_id);
create index if not exists pos_kds_item_status_order_idx on public.pos_kds_item_status(order_id);
alter table public.pos_kds_item_status enable row level security;
drop policy if exists "kds branch read" on public.pos_kds_item_status;
create policy "kds branch read" on public.pos_kds_item_status for select to authenticated using (
 branch_id = (select branch_id from public.pos_profiles where id=auth.uid())
);
drop policy if exists "kds branch write" on public.pos_kds_item_status;
create policy "kds branch write" on public.pos_kds_item_status for all to authenticated using (
 branch_id = (select branch_id from public.pos_profiles where id=auth.uid())
) with check (
 branch_id = (select branch_id from public.pos_profiles where id=auth.uid())
);

grant select,insert,update,delete on public.pos_kds_item_status to authenticated;
notify pgrst, 'reload schema';
