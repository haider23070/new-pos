-- NEXA branch-isolated cloud print queue
create table if not exists public.pos_print_jobs (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.pos_branches(id) on delete cascade,
  order_id uuid null references public.pos_orders(id) on delete set null,
  job_type text not null default 'RECEIPT',
  printer_type text not null default 'receipt',
  status text not null default 'pending' check (status in ('pending','processing','printed','failed')),
  payload jsonb not null default '{}'::jsonb,
  attempts integer not null default 0,
  error_message text,
  created_by uuid references auth.users(id) on delete set null,
  claimed_by uuid,
  created_at timestamptz not null default now(),
  claimed_at timestamptz,
  printed_at timestamptz,
  updated_at timestamptz not null default now()
);
create index if not exists pos_print_jobs_branch_status_idx on public.pos_print_jobs(branch_id,status,created_at);
alter table public.pos_print_jobs enable row level security;
drop policy if exists "branch users create print jobs" on public.pos_print_jobs;
create policy "branch users create print jobs" on public.pos_print_jobs for insert to authenticated with check (
 branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false limit 1)
);
drop policy if exists "branch users read print jobs" on public.pos_print_jobs;
create policy "branch users read print jobs" on public.pos_print_jobs for select to authenticated using (
 branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false limit 1)
);
drop policy if exists "branch users update print jobs" on public.pos_print_jobs;
create policy "branch users update print jobs" on public.pos_print_jobs for update to authenticated using (
 branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false limit 1)
) with check (
 branch_id=(select p.branch_id from public.pos_profiles p where p.id=auth.uid() and p.active is distinct from false limit 1)
);
