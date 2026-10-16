-- NEXA FINAL REBUILD LAYER
-- Adds production recipe-theoretical usage, inventory reconciliation, rider geofence attendance and live rider control.

alter table public.branches add column if not exists attendance_radius_m integer not null default 500;
alter table public.branches add column if not exists timezone text not null default 'Asia/Karachi';

-- Theoretical ingredient usage is separate from physical stock.
create table if not exists public.order_theoretical_usage(
 id uuid primary key default gen_random_uuid(),
 branch_id uuid not null references public.branches(id) on delete cascade,
 order_id uuid not null references public.orders(id) on delete cascade,
 ingredient_id uuid not null references public.inventory_ingredients(id) on delete restrict,
 quantity numeric(14,3) not null check(quantity>=0),
 unit text,
 created_at timestamptz not null default now(),
 unique(order_id,ingredient_id)
);
create index if not exists otu_branch_date_idx on public.order_theoretical_usage(branch_id,created_at desc);
create index if not exists otu_ingredient_idx on public.order_theoretical_usage(ingredient_id,created_at desc);
alter table public.order_theoretical_usage enable row level security;
do $$ begin create policy "final theoretical branch" on public.order_theoretical_usage for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;

create or replace function public.nexa_sync_order_theoretical_usage() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  if new.status='Completed' and old.status is distinct from 'Completed' then
    insert into order_theoretical_usage(branch_id,order_id,ingredient_id,quantity,unit)
    select new.branch_id,new.id,ri.ingredient_id,sum(oi.qty*ri.quantity),ii.unit
    from order_items oi
    join inventory_recipes rr on rr.product_id=oi.item_id and rr.branch_id=new.branch_id and rr.active=true
    join inventory_recipe_items ri on ri.recipe_id=rr.id
    join inventory_ingredients ii on ii.id=ri.ingredient_id
    where oi.order_id=new.id
    group by ri.ingredient_id,ii.unit
    on conflict(order_id,ingredient_id) do update set quantity=excluded.quantity,unit=excluded.unit,created_at=now();
  elsif old.status='Completed' and new.status is distinct from 'Completed' then
    delete from order_theoretical_usage where order_id=new.id;
  end if;
  return new;
end $$;
drop trigger if exists trg_nexa_theoretical_usage on public.orders;
create trigger trg_nexa_theoretical_usage after update of status on public.orders for each row execute function public.nexa_sync_order_theoretical_usage();

-- Reconciliation: book stock is physical ledger quantity. Expected closing subtracts theoretical recipe usage since last closing.
create or replace function public.nexa_inventory_reconciliation(p_as_of timestamptz default now())
returns table(ingredient_id uuid,name text,unit text,book_stock numeric,theoretical_used numeric,expected_stock numeric,min_stock numeric,avg_cost numeric,variance_value_per_unit numeric)
language sql stable security definer set search_path=public as $$
with last_close as (
 select max(ic.created_at) as at from inventory_closings ic where ic.branch_id=nexa_my_branch() and ic.created_at<=p_as_of
), usage as (
 select u.ingredient_id,sum(u.quantity)::numeric used
 from order_theoretical_usage u,last_close lc
 where u.branch_id=nexa_my_branch() and u.created_at>coalesce(lc.at,date_trunc('day',p_as_of)) and u.created_at<=p_as_of
 group by u.ingredient_id
)
select i.id,i.name,i.unit,i.current_stock,coalesce(u.used,0),i.current_stock-coalesce(u.used,0),i.min_stock,i.avg_cost,i.avg_cost
from inventory_ingredients i left join usage u on u.ingredient_id=i.id
where i.branch_id=nexa_my_branch() and i.active=true order by i.name
$$;
grant execute on function public.nexa_inventory_reconciliation(timestamptz) to authenticated;

-- Accurate distance in meters for rider attendance.
create or replace function public.nexa_distance_m(lat1 numeric,lon1 numeric,lat2 numeric,lon2 numeric) returns numeric
language sql immutable as $$
 select 6371000 * 2 * asin(sqrt(power(sin(radians((lat2-lat1)/2)),2)+cos(radians(lat1))*cos(radians(lat2))*power(sin(radians((lon2-lon1)/2)),2)))
$$;

create or replace function public.nexa_rider_start_shift(p_rider_id uuid,p_lat numeric,p_lng numeric) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_branch uuid;v_blat numeric;v_blng numeric;v_radius integer;v_distance numeric;v_uid uuid:=auth.uid();begin
 select r.branch_id into v_branch from riders r where r.id=p_rider_id and r.profile_id=v_uid;
 if v_branch is null or v_branch<>nexa_my_branch() then raise exception 'Rider account is not linked to this branch'; end if;
 select latitude,longitude,attendance_radius_m into v_blat,v_blng,v_radius from branches where id=v_branch;
 if v_blat is null or v_blng is null then raise exception 'Restaurant attendance location is not configured'; end if;
 v_distance:=nexa_distance_m(p_lat,p_lng,v_blat,v_blng);
 if v_distance>coalesce(v_radius,500) then raise exception 'You are % m from the restaurant. Move within % m to mark attendance',round(v_distance),coalesce(v_radius,500); end if;
 if exists(select 1 from rider_attendance where rider_id=p_rider_id and ended_at is null) then raise exception 'Shift already active'; end if;
 insert into rider_attendance(rider_id,branch_id,start_lat,start_lng) values(p_rider_id,v_branch,p_lat,p_lng) returning id into v_id;
 update riders set on_duty=true,status='Available',checked_in_at=now() where id=p_rider_id;
 insert into rider_locations(rider_id,branch_id,latitude,longitude) values(p_rider_id,v_branch,p_lat,p_lng);
 return v_id;
end $$;

create or replace function public.nexa_live_riders()
returns table(rider_id uuid,name text,phone text,status text,on_duty boolean,latitude numeric,longitude numeric,accuracy_m numeric,recorded_at timestamptz,active_delivery_id uuid,order_id uuid,token bigint)
language sql stable security definer set search_path=public as $$
 select r.id,r.name,r.phone,r.status,r.on_duty,l.latitude,l.longitude,l.accuracy_m,l.recorded_at,d.id,d.order_id,o.token
 from riders r
 left join lateral(select rl.latitude,rl.longitude,rl.accuracy_m,rl.recorded_at from rider_locations rl where rl.rider_id=r.id order by rl.recorded_at desc limit 1) l on true
 left join lateral(select dx.id,dx.order_id from deliveries dx where dx.rider_id=r.id and dx.status not in('Delivered','Cancelled') order by dx.assigned_at desc nulls last limit 1) d on true
 left join orders o on o.id=d.order_id
 where r.branch_id=nexa_my_branch() order by r.on_duty desc,r.name
$$;
grant execute on function public.nexa_live_riders() to authenticated;

-- Branch location/settings helper for management.
create or replace function public.nexa_save_branch_geo(p_lat numeric,p_lng numeric,p_delivery_radius_km numeric default 8,p_attendance_radius_m integer default 500)
returns void language plpgsql security definer set search_path=public as $$
begin
 if nexa_my_role() not in('Admin','Manager') then raise exception 'Not allowed'; end if;
 update branches set latitude=p_lat,longitude=p_lng,delivery_radius_km=greatest(.5,p_delivery_radius_km),attendance_radius_m=greatest(50,least(5000,p_attendance_radius_m)) where id=nexa_my_branch();
end $$;
grant execute on function public.nexa_save_branch_geo(numeric,numeric,numeric,integer) to authenticated;

-- Helpful indexes
create index if not exists orders_branch_status_created_idx on public.orders(branch_id,status,created_at desc);
create index if not exists deliveries_branch_status_idx on public.deliveries(branch_id,status,assigned_at desc);
create index if not exists inventory_ing_branch_active_idx on public.inventory_ingredients(branch_id,active,name);

create or replace function public.nexa_save_recipe(p_product_id uuid,p_name text,p_yield_qty numeric,p_items jsonb)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=nexa_my_branch();v_id uuid;v jsonb;begin
 if nexa_my_role() not in('Admin','Manager') then raise exception 'Not allowed'; end if;
 if p_product_id is null or coalesce(trim(p_name),'')='' then raise exception 'Menu item and recipe name are required'; end if;
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'Add at least one ingredient'; end if;
 insert into inventory_recipes(branch_id,product_id,name,yield_qty,active) values(v_branch,p_product_id,p_name,greatest(p_yield_qty,0.001),true)
 returning id into v_id;
 for v in select * from jsonb_array_elements(p_items) loop
  insert into inventory_recipe_items(recipe_id,ingredient_id,quantity) values(v_id,(v->>'ingredient_id')::uuid,(v->>'quantity')::numeric);
 end loop;
 return v_id;
end $$;
grant execute on function public.nexa_save_recipe(uuid,text,numeric,jsonb) to authenticated;

-- One-time safe bootstrap after creating the first Auth user.
create or replace function public.nexa_bootstrap_first_admin(p_name text default 'NEXA Admin') returns void
language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();v_email text;begin
 if v_uid is null then raise exception 'Login first'; end if;
 if exists(select 1 from profiles where lower(role)='admin' and active=true) then raise exception 'An Admin already exists'; end if;
 select email into v_email from auth.users where id=v_uid;
 insert into profiles(id,name,email,role,active) values(v_uid,coalesce(nullif(trim(p_name),''),'NEXA Admin'),v_email,'Admin',true)
 on conflict(id) do update set name=excluded.name,email=excluded.email,role='Admin',active=true;
end $$;
grant execute on function public.nexa_bootstrap_first_admin(text) to authenticated;
