-- NEXA v26: delivery orders must be visible even if an older client failed to create the queue row.
create or replace function public.nexa_ensure_delivery_queue(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public
as $$
declare
  v_order public.orders%rowtype;
  v_customer public.customers%rowtype;
  v_delivery_id uuid;
  v_role text:=public.nexa_my_role();
begin
  select * into v_order from public.orders where id=p_order_id;
  if v_order.id is null then raise exception 'Order not found'; end if;
  if lower(replace(coalesce(v_order.order_type,''),'_','-')) not in ('delivery','home-delivery') then
    raise exception 'Order is not a delivery order';
  end if;
  if v_role <> 'Developer' and v_order.branch_id <> public.nexa_my_branch() then
    raise exception 'You cannot access another branch order';
  end if;
  if v_order.customer_id is not null then select * into v_customer from public.customers where id=v_order.customer_id; end if;
  insert into public.deliveries(order_id,branch_id,customer_name,customer_phone,delivery_address,status)
  values(v_order.id,v_order.branch_id,coalesce(v_customer.name,'Delivery Customer'),v_customer.phone,v_customer.address,coalesce(nullif(v_order.delivery_status,''),'Awaiting Rider'))
  on conflict(order_id) do update set
    customer_name=coalesce(excluded.customer_name,public.deliveries.customer_name),
    customer_phone=coalesce(excluded.customer_phone,public.deliveries.customer_phone),
    delivery_address=coalesce(excluded.delivery_address,public.deliveries.delivery_address)
  returning id into v_delivery_id;
  update public.orders set delivery_status=coalesce(nullif(delivery_status,''),'Awaiting Rider') where id=p_order_id;
  return v_delivery_id;
end $$;
grant execute on function public.nexa_ensure_delivery_queue(uuid) to authenticated;

-- Repair every existing non-draft delivery order now.
insert into public.deliveries(order_id,branch_id,customer_name,customer_phone,delivery_address,status)
select o.id,o.branch_id,coalesce(c.name,'Delivery Customer'),c.phone,c.address,coalesce(nullif(o.delivery_status,''),'Awaiting Rider')
from public.orders o left join public.customers c on c.id=o.customer_id
where lower(replace(coalesce(o.order_type,''),'_','-')) in ('delivery','home-delivery') and lower(coalesce(o.status,'')) <> 'draft'
on conflict(order_id) do nothing;
notify pgrst,'reload schema';
