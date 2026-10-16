-- NEXA POS: allow Admin/Manager to read staff in their own branch.
-- Safe to run more than once.

create or replace function public.pos_can_manage_branch(target_branch uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.pos_profiles p
    where p.id = auth.uid()
      and p.active is true
      and p.role in ('Admin','Manager')
      and p.branch_id = target_branch
  );
$$;

grant execute on function public.pos_can_manage_branch(uuid) to authenticated;

alter table public.pos_profiles enable row level security;

drop policy if exists pos_profiles_staff_read on public.pos_profiles;
create policy pos_profiles_staff_read
on public.pos_profiles
for select
to authenticated
using (
  id = auth.uid()
  or public.pos_can_manage_branch(branch_id)
);
