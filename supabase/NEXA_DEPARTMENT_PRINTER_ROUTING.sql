-- NEXA Department Printer Routing v1
-- Run once in Supabase SQL Editor.

alter table public.pos_print_agents
  add column if not exists available_printers jsonb not null default '[]'::jsonb;

-- Existing pos_branch_printers is the source of truth for department -> Windows printer routing.
create unique index if not exists pos_branch_printers_branch_department_uidx
  on public.pos_branch_printers(branch_id, department_id)
  where department_id is not null;

-- Ensure authenticated branch users can see their own branch agents/printer discovery.
alter table public.pos_print_agents enable row level security;
drop policy if exists "branch users read print agents" on public.pos_print_agents;
create policy "branch users read print agents" on public.pos_print_agents
for select to authenticated using (
  branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false limit 1)
);

-- Admin/Manager can manage department routes for their own branch.
alter table public.pos_branch_printers enable row level security;
drop policy if exists "management read branch printers" on public.pos_branch_printers;
create policy "management read branch printers" on public.pos_branch_printers
for select to authenticated using (
  branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false limit 1)
);
drop policy if exists "management insert branch printers" on public.pos_branch_printers;
create policy "management insert branch printers" on public.pos_branch_printers
for insert to authenticated with check (
  branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false and p.role in ('Admin','Manager') limit 1)
);
drop policy if exists "management update branch printers" on public.pos_branch_printers;
create policy "management update branch printers" on public.pos_branch_printers
for update to authenticated using (
  branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false and p.role in ('Admin','Manager') limit 1)
) with check (
  branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false and p.role in ('Admin','Manager') limit 1)
);

-- v2: reliable authenticated printer discovery for the POS dropdown.
-- SECURITY DEFINER only returns printers for the signed-in user's own branch.
create or replace function public.nexa_branch_available_printers()
returns jsonb
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    jsonb_agg(distinct p.printer_name order by p.printer_name)
      filter (where p.printer_name is not null and btrim(p.printer_name) <> ''),
    '[]'::jsonb
  )
  from public.pos_print_agents a
  cross join lateral jsonb_array_elements_text(coalesce(a.available_printers,'[]'::jsonb)) p(printer_name)
  where a.branch_id = (
    select pp.branch_id
    from public.pos_profiles pp
    where pp.id = auth.uid() and pp.active is distinct from false
    limit 1
  );
$$;
revoke all on function public.nexa_branch_available_printers() from public;
grant execute on function public.nexa_branch_available_printers() to authenticated;
