-- NEXA Rider GPS v5 - matches the confirmed live schema.
-- Existing columns used: pos_riders.profile_id, pos_riders.on_duty, pos_riders.phone.
-- pos_profiles.phone is NOT referenced.

create table if not exists public.pos_rider_attendance (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.pos_riders(id) on delete cascade,
  branch_id uuid not null references public.pos_branches(id) on delete cascade,
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  start_latitude double precision,
  start_longitude double precision,
  created_at timestamptz not null default now()
);

create table if not exists public.pos_rider_locations (
  id uuid primary key default gen_random_uuid(),
  rider_id uuid not null references public.pos_riders(id) on delete cascade,
  branch_id uuid not null references public.pos_branches(id) on delete cascade,
  latitude double precision not null,
  longitude double precision not null,
  accuracy_m double precision,
  recorded_at timestamptz not null default now()
);

create index if not exists pos_rider_locations_rider_time_idx on public.pos_rider_locations(rider_id, recorded_at desc);
create index if not exists pos_rider_attendance_rider_time_idx on public.pos_rider_attendance(rider_id, started_at desc);
create unique index if not exists pos_riders_profile_id_uq on public.pos_riders(profile_id) where profile_id is not null;

alter table public.pos_rider_attendance enable row level security;
alter table public.pos_rider_locations enable row level security;

drop policy if exists pos_rider_attendance_auth on public.pos_rider_attendance;
create policy pos_rider_attendance_auth on public.pos_rider_attendance for all to authenticated using (true) with check (true);
drop policy if exists pos_rider_locations_auth on public.pos_rider_locations;
create policy pos_rider_locations_auth on public.pos_rider_locations for all to authenticated using (true) with check (true);

do $$ begin
  alter publication supabase_realtime add table public.pos_rider_locations;
exception when duplicate_object then null;
end $$;
