-- NEXA Phase 10: rider mobile app, order-taker workflow and public ordering/tracking
create extension if not exists pgcrypto;
alter table public.branches add column if not exists latitude numeric(10,7);
alter table public.branches add column if not exists longitude numeric(10,7);
alter table public.branches add column if not exists delivery_radius_km numeric(8,2) default 8;
alter table public.orders add column if not exists public_tracking_code text unique;
create index if not exists orders_public_tracking_idx on public.orders(public_tracking_code);

create table if not exists public.rider_attendance(
 id uuid primary key default gen_random_uuid(), rider_id uuid not null references public.riders(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete cascade, started_at timestamptz not null default now(), ended_at timestamptz,
 start_lat numeric(10,7), start_lng numeric(10,7), end_lat numeric(10,7), end_lng numeric(10,7)
);
create table if not exists public.rider_locations(
 id bigint generated always as identity primary key, rider_id uuid not null references public.riders(id) on delete cascade,
 branch_id uuid not null references public.branches(id) on delete cascade, latitude numeric(10,7) not null, longitude numeric(10,7) not null,
 accuracy_m numeric(10,2), recorded_at timestamptz not null default now()
);
create index if not exists rider_locations_latest_idx on public.rider_locations(rider_id,recorded_at desc);
alter table public.rider_attendance enable row level security; alter table public.rider_locations enable row level security;
do $$ begin create policy "p10 attendance branch" on public.rider_attendance for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin create policy "p10 locations branch" on public.rider_locations for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.rider_locations; exception when duplicate_object then null; end $$;

create or replace function public.nexa_rider_start_shift(p_rider_id uuid,p_lat numeric,p_lng numeric) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_branch uuid; begin select branch_id into v_branch from riders where id=p_rider_id; if v_branch is null or v_branch<>nexa_my_branch() then raise exception 'Rider is not in your branch'; end if; if exists(select 1 from rider_attendance where rider_id=p_rider_id and ended_at is null) then raise exception 'Shift already active'; end if; insert into rider_attendance(rider_id,branch_id,start_lat,start_lng) values(p_rider_id,v_branch,p_lat,p_lng) returning id into v_id; update riders set on_duty=true,status='Available',checked_in_at=now() where id=p_rider_id; insert into rider_locations(rider_id,branch_id,latitude,longitude) values(p_rider_id,v_branch,p_lat,p_lng); return v_id; end $$;
create or replace function public.nexa_rider_end_shift(p_rider_id uuid) returns void language plpgsql security definer set search_path=public as $$
begin if not exists(select 1 from riders where id=p_rider_id and branch_id=nexa_my_branch()) then raise exception 'Not allowed'; end if; update rider_attendance set ended_at=now() where rider_id=p_rider_id and ended_at is null; update riders set on_duty=false,status='Off Duty',checked_out_at=now() where id=p_rider_id; end $$;
grant execute on function public.nexa_rider_start_shift(uuid,numeric,numeric) to authenticated; grant execute on function public.nexa_rider_end_shift(uuid) to authenticated;

-- Safe public read APIs: expose only active branch/menu information needed by customers.
create or replace function public.nexa_public_branches() returns table(id uuid,name text,address text,phone text,latitude numeric,longitude numeric,delivery_radius_km numeric) language sql stable security definer set search_path=public as $$ select b.id,b.name,b.address,b.phone,b.latitude,b.longitude,b.delivery_radius_km from branches b where coalesce(b.active,true)=true order by b.name $$;
create or replace function public.nexa_public_menu(p_branch_id uuid) returns table(item_id uuid,variant_id uuid,name text,variant_name text,price numeric,category_name text) language sql stable security definer set search_path=public as $$ select i.id,v.id,i.name,v.name,v.price,c.name from menu_items i join menu_variants v on v.item_id=i.id left join categories c on c.id=i.category_id where i.branch_id=p_branch_id and coalesce(i.active,true)=true and coalesce(v.active,true)=true order by c.sort_order,c.name,i.name,v.price $$;
grant execute on function public.nexa_public_branches() to anon,authenticated; grant execute on function public.nexa_public_menu(uuid) to anon,authenticated;

create or replace function public.nexa_public_place_order(p_branch_id uuid,p_customer_name text,p_phone text,p_address text,p_items jsonb) returns jsonb language plpgsql security definer set search_path=public as $$
declare v_customer uuid;v_order uuid;v_total numeric:=0;v_code text:=upper(substr(replace(gen_random_uuid()::text,'-',''),1,10));r jsonb;v_price numeric;v_name text;v_item uuid; begin
 if coalesce(trim(p_customer_name),'')='' or coalesce(trim(p_phone),'')='' or coalesce(trim(p_address),'')='' then raise exception 'Name, phone and delivery address are required'; end if;
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'Cart is empty'; end if;
 insert into customers(branch_id,name,phone,address) values(p_branch_id,p_customer_name,p_phone,p_address) returning id into v_customer;
 for r in select * from jsonb_array_elements(p_items) loop select v.price,i.name,i.id into v_price,v_name,v_item from menu_variants v join menu_items i on i.id=v.item_id where v.id=(r->>'variant_id')::uuid and i.branch_id=p_branch_id and i.active=true; if v_price is null then raise exception 'Invalid menu item'; end if; v_total:=v_total+(v_price*greatest(1,(r->>'qty')::numeric)); end loop;
 insert into orders(branch_id,customer_id,order_type,status,kitchen_status,total,grand_total,public_tracking_code) values(p_branch_id,v_customer,'Delivery','Placed','Processing',v_total,v_total,v_code) returning id into v_order;
 for r in select * from jsonb_array_elements(p_items) loop select v.price,i.name,i.id into v_price,v_name,v_item from menu_variants v join menu_items i on i.id=v.item_id where v.id=(r->>'variant_id')::uuid; insert into order_items(order_id,item_id,variant_id,name,qty,unit_price,status) values(v_order,v_item,(r->>'variant_id')::uuid,v_name,greatest(1,(r->>'qty')::numeric),v_price,'Pending'); end loop;
 insert into deliveries(order_id,branch_id,customer_name,customer_phone,delivery_address,status) values(v_order,p_branch_id,p_customer_name,p_phone,p_address,'Awaiting Rider');
 return jsonb_build_object('order_id',v_order,'tracking_code',v_code,'status','Placed','grand_total',v_total);
end $$; grant execute on function public.nexa_public_place_order(uuid,text,text,text,jsonb) to anon,authenticated;

create or replace function public.nexa_public_track_order(p_code text,p_phone text) returns table(tracking_code text,token bigint,status text,kitchen_status text,delivery_status text,branch_name text,rider_name text,rider_lat numeric,rider_lng numeric,location_time timestamptz) language sql stable security definer set search_path=public as $$
 select o.public_tracking_code,o.token,o.status,o.kitchen_status,d.status,b.name,r.name,rl.latitude,rl.longitude,rl.recorded_at
 from orders o join customers c on c.id=o.customer_id join branches b on b.id=o.branch_id left join deliveries d on d.order_id=o.id left join riders r on r.id=d.rider_id left join lateral(select x.latitude,x.longitude,x.recorded_at from rider_locations x where x.rider_id=r.id order by x.recorded_at desc limit 1) rl on true
 where upper(o.public_tracking_code)=upper(trim(p_code)) and regexp_replace(c.phone,'\D','','g')=regexp_replace(p_phone,'\D','','g') limit 1 $$;
grant execute on function public.nexa_public_track_order(text,text) to anon,authenticated;
