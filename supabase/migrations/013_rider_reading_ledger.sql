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
