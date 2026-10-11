-- NEXA v25: make every placed Delivery order enter the dispatch queue.
-- Also backfills existing delivery orders and allows Developer to dispatch across the selected/home branch.

create or replace function public.nexa_sync_delivery_for_order()
returns trigger
language plpgsql
security definer
set search_path=public
as $$
declare
  v_customer public.customers%rowtype;
begin
  if lower(replace(coalesce(new.order_type,''),'_','-')) in ('delivery','home-delivery')
     and lower(coalesce(new.status,'')) <> 'draft' then
    if new.customer_id is not null then
      select * into v_customer from public.customers where id=new.customer_id and branch_id=new.branch_id;
    end if;
    insert into public.deliveries(
      order_id,branch_id,customer_name,customer_phone,delivery_address,status
    ) values(
      new.id,new.branch_id,
      coalesce(v_customer.name,'Delivery Customer'),
      v_customer.phone,
      v_customer.address,
      'Awaiting Rider'
    )
    on conflict(order_id) do update set
      branch_id=excluded.branch_id,
      customer_name=coalesce(excluded.customer_name,public.deliveries.customer_name),
      customer_phone=coalesce(excluded.customer_phone,public.deliveries.customer_phone),
      delivery_address=coalesce(excluded.delivery_address,public.deliveries.delivery_address);
    update public.orders set delivery_status=coalesce(delivery_status,'Awaiting Rider') where id=new.id;
  end if;
  return new;
end $$;

drop trigger if exists trg_nexa_sync_delivery_for_order on public.orders;
create trigger trg_nexa_sync_delivery_for_order
after insert or update of order_type,status,customer_id on public.orders
for each row execute function public.nexa_sync_delivery_for_order();

-- Backfill delivery queue for orders that were already created before this fix.
insert into public.deliveries(order_id,branch_id,customer_name,customer_phone,delivery_address,status)
select o.id,o.branch_id,coalesce(c.name,'Delivery Customer'),c.phone,c.address,coalesce(nullif(o.delivery_status,''),'Awaiting Rider')
from public.orders o
left join public.customers c on c.id=o.customer_id and c.branch_id=o.branch_id
where lower(replace(coalesce(o.order_type,''),'_','-')) in ('delivery','home-delivery')
  and lower(coalesce(o.status,'')) <> 'draft'
on conflict(order_id) do update set
 branch_id=excluded.branch_id,
 customer_name=coalesce(excluded.customer_name,public.deliveries.customer_name),
 customer_phone=coalesce(excluded.customer_phone,public.deliveries.customer_phone),
 delivery_address=coalesce(excluded.delivery_address,public.deliveries.delivery_address);

update public.orders o
set delivery_status=coalesce(nullif(o.delivery_status,''),d.status,'Awaiting Rider')
from public.deliveries d
where d.order_id=o.id and lower(replace(coalesce(o.order_type,''),'_','-')) in ('delivery','home-delivery');

create or replace function public.nexa_assign_rider(p_delivery_id uuid,p_rider_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_branch uuid; v_role text:=public.nexa_my_role();
begin
 select branch_id into v_branch from public.deliveries where id=p_delivery_id;
 if v_branch is null then raise exception 'Delivery not found'; end if;
 if v_role not in ('Developer','Admin','Manager','Dispatcher') then raise exception 'Your role cannot assign orders to riders'; end if;
 if v_role <> 'Developer' and v_branch <> public.nexa_my_branch() then raise exception 'You cannot dispatch another branch order'; end if;
 if not exists(select 1 from public.riders where id=p_rider_id and branch_id=v_branch and on_duty=true) then raise exception 'Rider is not available for this branch'; end if;
 update public.deliveries set rider_id=p_rider_id,status='Assigned',assigned_at=now() where id=p_delivery_id;
 update public.orders set delivery_status='Assigned' where id=(select order_id from public.deliveries where id=p_delivery_id);
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,metadata)
 values(v_branch,public.nexa_my_user_id(),'RIDER_ASSIGNED','delivery',p_delivery_id,jsonb_build_object('rider_id',p_rider_id));
end $$;
grant execute on function public.nexa_assign_rider(uuid,uuid) to authenticated;

notify pgrst,'reload schema';
