-- NEXA Rider GPS v7 - clean repair for rider linking/check-in/check-out/GPS.
-- Safe to run after V5/V6. Replaces the broken functions; does not delete riders or orders.
-- Confirmed schema:
-- pos_profiles(id,email,name,role,branch_id,active,...)
-- pos_riders(id,branch_id,name,phone,active,status,profile_id,on_duty,...)
-- pos_orders(...,rider_id,...)

-- Required support tables (idempotent)
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

create index if not exists pos_rider_locations_rider_time_idx
  on public.pos_rider_locations(rider_id, recorded_at desc);
create index if not exists pos_rider_attendance_rider_time_idx
  on public.pos_rider_attendance(rider_id, started_at desc);
create unique index if not exists pos_riders_profile_id_uq
  on public.pos_riders(profile_id) where profile_id is not null;

alter table public.pos_rider_attendance enable row level security;
alter table public.pos_rider_locations enable row level security;

drop policy if exists pos_rider_attendance_auth on public.pos_rider_attendance;
create policy pos_rider_attendance_auth on public.pos_rider_attendance
  for all to authenticated using (true) with check (true);

drop policy if exists pos_rider_locations_auth on public.pos_rider_locations;
create policy pos_rider_locations_auth on public.pos_rider_locations
  for all to authenticated using (true) with check (true);

-- Remove only old function definitions. No data is removed.
drop function if exists public.nexa_pos_link_current_rider();
drop function if exists public.nexa_pos_rider_check_in(uuid,double precision,double precision,double precision);
drop function if exists public.nexa_pos_rider_check_out(uuid);
drop function if exists public.nexa_pos_rider_push_location(uuid,double precision,double precision,double precision);

create function public.nexa_pos_link_current_rider()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.pos_profiles%rowtype;
  v_rider_id uuid;
  v_matches integer := 0;
begin
  if v_uid is null then
    raise exception 'Authentication required';
  end if;

  select * into v_profile
  from public.pos_profiles
  where id = v_uid and active = true
  limit 1;

  if not found then
    raise exception 'Active POS profile not found';
  end if;

  if lower(replace(coalesce(v_profile.role,''), ' ', '')) not in
     ('rider','deliveryboy','deliveryrider') then
    raise exception 'This account is not a rider account';
  end if;

  -- Normal path: this login is already linked to one rider.
  select r.id into v_rider_id
  from public.pos_riders r
  where r.profile_id = v_uid and r.active = true
  order by r.created_at asc, r.id asc
  limit 1;

  if v_rider_id is not null then
    return v_rider_id;
  end if;

  -- Legacy/self-heal path. Count matching unlinked riders by branch + exact name.
  select count(*) into v_matches
  from public.pos_riders r
  where r.profile_id is null
    and r.branch_id = v_profile.branch_id
    and r.active = true
    and lower(trim(coalesce(r.name,''))) = lower(trim(coalesce(v_profile.name,'')));

  if v_matches = 1 then
    select r.id into v_rider_id
    from public.pos_riders r
    where r.profile_id is null
      and r.branch_id = v_profile.branch_id
      and r.active = true
      and lower(trim(coalesce(r.name,''))) = lower(trim(coalesce(v_profile.name,'')))
    order by r.created_at asc, r.id asc
    limit 1;

    update public.pos_riders
      set profile_id = v_uid, updated_at = now()
    where id = v_rider_id;

    return v_rider_id;
  elsif v_matches = 0 then
    raise exception 'No rider record is linked to this login. Set pos_riders.profile_id to this rider login profile id.';
  else
    raise exception 'More than one unlinked rider has this name. Link the correct pos_riders.profile_id manually.';
  end if;
end;
$$;

grant execute on function public.nexa_pos_link_current_rider() to authenticated;

create function public.nexa_pos_rider_check_in(
  p_rider_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy double precision default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_branch uuid;
  v_attendance uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  if p_lat is null or p_lng is null then raise exception 'GPS location is required'; end if;

  select r.branch_id into v_branch
  from public.pos_riders r
  where r.id = p_rider_id
    and r.profile_id = v_uid
    and r.active = true
  limit 1;

  if v_branch is null then
    raise exception 'This rider is not linked to the logged-in account';
  end if;

  select a.id into v_attendance
  from public.pos_rider_attendance a
  where a.rider_id = p_rider_id and a.ended_at is null
  order by a.started_at desc
  limit 1;

  if v_attendance is null then
    insert into public.pos_rider_attendance
      (rider_id, branch_id, started_at, start_latitude, start_longitude)
    values
      (p_rider_id, v_branch, now(), p_lat, p_lng)
    returning id into v_attendance;
  end if;

  update public.pos_riders
    set on_duty = true, status = 'Available', updated_at = now()
  where id = p_rider_id;

  insert into public.pos_rider_locations
    (rider_id, branch_id, latitude, longitude, accuracy_m, recorded_at)
  values
    (p_rider_id, v_branch, p_lat, p_lng, p_accuracy, now());

  return v_attendance;
end;
$$;

grant execute on function public.nexa_pos_rider_check_in(uuid,double precision,double precision,double precision) to authenticated;

create function public.nexa_pos_rider_check_out(p_rider_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  if not exists (
    select 1 from public.pos_riders r
    where r.id = p_rider_id and r.profile_id = v_uid and r.active = true
  ) then
    raise exception 'This rider is not linked to the logged-in account';
  end if;

  update public.pos_rider_attendance
    set ended_at = now()
  where rider_id = p_rider_id and ended_at is null;

  update public.pos_riders
    set on_duty = false, status = 'Off Duty', updated_at = now()
  where id = p_rider_id;
end;
$$;

grant execute on function public.nexa_pos_rider_check_out(uuid) to authenticated;

create function public.nexa_pos_rider_push_location(
  p_rider_id uuid,
  p_lat double precision,
  p_lng double precision,
  p_accuracy double precision default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_branch uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;

  select r.branch_id into v_branch
  from public.pos_riders r
  where r.id = p_rider_id
    and r.profile_id = v_uid
    and r.active = true
    and r.on_duty = true
  limit 1;

  if v_branch is null then
    raise exception 'Rider is not checked in';
  end if;

  insert into public.pos_rider_locations
    (rider_id, branch_id, latitude, longitude, accuracy_m, recorded_at)
  values
    (p_rider_id, v_branch, p_lat, p_lng, p_accuracy, now());
end;
$$;

grant execute on function public.nexa_pos_rider_push_location(uuid,double precision,double precision,double precision) to authenticated;

-- Realtime registration is optional; ignore if already registered.
do $$
begin
  alter publication supabase_realtime add table public.pos_rider_locations;
exception
  when duplicate_object then null;
end $$;
