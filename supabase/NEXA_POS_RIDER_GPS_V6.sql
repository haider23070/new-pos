-- NEXA Rider GPS v6 - reliable Rider Check In / Check Out for the confirmed pos_* schema.
-- Run AFTER V5 (or after pos_rider_attendance and pos_rider_locations already exist).
-- Uses only confirmed columns from pos_profiles, pos_riders and pos_orders.

create or replace function public.nexa_pos_link_current_rider()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_profile public.pos_profiles%rowtype;
  v_rider_id uuid;
  v_matches integer;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select * into v_profile from public.pos_profiles where id=v_uid and active=true;
  if v_profile.id is null then raise exception 'Active POS profile not found'; end if;
  if lower(replace(coalesce(v_profile.role,''),' ','')) not in ('rider','deliveryboy','deliveryrider') then
    raise exception 'This account is not a rider account';
  end if;

  select id into v_rider_id from public.pos_riders
  where profile_id=v_uid and active=true limit 1;
  if v_rider_id is not null then return v_rider_id; end if;

  select count(*), min(id) into v_matches, v_rider_id
  from public.pos_riders
  where branch_id=v_profile.branch_id and active=true
    and lower(trim(name))=lower(trim(v_profile.name));

  if v_matches=1 then
    update public.pos_riders set profile_id=v_uid, updated_at=now() where id=v_rider_id;
    return v_rider_id;
  elsif v_matches=0 then
    raise exception 'No rider record is linked to this login. Create/choose the rider in Rider Management with the same name as this staff account.';
  else
    raise exception 'More than one rider has this name. Link the correct pos_riders.profile_id to this login.';
  end if;
end $$;

grant execute on function public.nexa_pos_link_current_rider() to authenticated;

create or replace function public.nexa_pos_rider_check_in(
  p_rider_id uuid, p_lat double precision, p_lng double precision, p_accuracy double precision default null
) returns uuid
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

  select branch_id into v_branch from public.pos_riders
  where id=p_rider_id and profile_id=v_uid and active=true;
  if v_branch is null then raise exception 'This rider is not linked to the logged-in account'; end if;

  select id into v_attendance from public.pos_rider_attendance
  where rider_id=p_rider_id and ended_at is null order by started_at desc limit 1;

  if v_attendance is null then
    insert into public.pos_rider_attendance(rider_id,branch_id,started_at,start_latitude,start_longitude)
    values(p_rider_id,v_branch,now(),p_lat,p_lng) returning id into v_attendance;
  end if;

  update public.pos_riders set on_duty=true,status='Available',updated_at=now() where id=p_rider_id;
  insert into public.pos_rider_locations(rider_id,branch_id,latitude,longitude,accuracy_m,recorded_at)
  values(p_rider_id,v_branch,p_lat,p_lng,p_accuracy,now());
  return v_attendance;
end $$;

grant execute on function public.nexa_pos_rider_check_in(uuid,double precision,double precision,double precision) to authenticated;

create or replace function public.nexa_pos_rider_check_out(p_rider_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); begin
  if not exists(select 1 from public.pos_riders where id=p_rider_id and profile_id=v_uid and active=true) then
    raise exception 'This rider is not linked to the logged-in account';
  end if;
  update public.pos_rider_attendance set ended_at=now()
    where rider_id=p_rider_id and ended_at is null;
  update public.pos_riders set on_duty=false,status='Off Duty',updated_at=now() where id=p_rider_id;
end $$;

grant execute on function public.nexa_pos_rider_check_out(uuid) to authenticated;

create or replace function public.nexa_pos_rider_push_location(
  p_rider_id uuid, p_lat double precision, p_lng double precision, p_accuracy double precision default null
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare v_uid uuid := auth.uid(); v_branch uuid; begin
  select branch_id into v_branch from public.pos_riders
    where id=p_rider_id and profile_id=v_uid and active=true and on_duty=true;
  if v_branch is null then raise exception 'Rider is not checked in'; end if;
  insert into public.pos_rider_locations(rider_id,branch_id,latitude,longitude,accuracy_m,recorded_at)
  values(p_rider_id,v_branch,p_lat,p_lng,p_accuracy,now());
end $$;

grant execute on function public.nexa_pos_rider_push_location(uuid,double precision,double precision,double precision) to authenticated;
