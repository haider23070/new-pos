-- NEXA production hardening: atomic orders/payments, rider security, GPS throttling, audit integrity.
create extension if not exists pgcrypto;

-- Call Center/Dispatcher may create orders but may never collect money.
drop policy if exists "p9 payments insert by role" on public.payments;
create policy "p21 payments insert by role" on public.payments for insert to authenticated
with check (
  public.nexa_my_role() in ('Admin','Manager','Cashier')
  and exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())
);

-- Atomic staff order creation. Prices are always resolved server-side; the browser cannot forge them.
create or replace function public.nexa_create_order(
 p_order_type text,p_customer_id uuid,p_table_id uuid,p_shift_id uuid,p_items jsonb,
 p_discount numeric default 0,p_tax numeric default 0,p_notes text default null,p_draft boolean default false
) returns uuid language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=public.nexa_my_branch();v_role text:=public.nexa_my_role();v_order uuid;v_subtotal numeric:=0;v_item jsonb;v_price numeric;v_name text;v_product uuid;v_qty numeric;v_variant uuid;
begin
 if v_branch is null then raise exception 'No branch assigned'; end if;
 if v_role not in ('Admin','Manager','Cashier','Call Center','Dispatcher','Order Taker') then raise exception 'Your role cannot create orders'; end if;
 if jsonb_array_length(coalesce(p_items,'[]'::jsonb))=0 then raise exception 'Add at least one item'; end if;
 if p_customer_id is not null and not exists(select 1 from customers where id=p_customer_id and branch_id=v_branch) then raise exception 'Invalid customer'; end if;
 if p_table_id is not null and not exists(select 1 from restaurant_tables where id=p_table_id and branch_id=v_branch) then raise exception 'Invalid table'; end if;
 if p_shift_id is not null and not exists(select 1 from shifts where id=p_shift_id and branch_id=v_branch and lower(status)='open') then raise exception 'Shift is not open'; end if;
 for v_item in select * from jsonb_array_elements(p_items) loop
   v_variant:=nullif(v_item->>'variant_id','')::uuid; v_qty:=greatest(0.001,coalesce((v_item->>'qty')::numeric,1));
   select mv.price,mi.name,mi.id into v_price,v_name,v_product from menu_variants mv join menu_items mi on mi.id=mv.item_id
   where mv.id=v_variant and mi.branch_id=v_branch and coalesce(mi.active,true) and coalesce(mv.active,true);
   if v_product is null then raise exception 'A menu item is invalid or inactive'; end if;
   v_subtotal:=v_subtotal+(v_price*v_qty);
 end loop;
 insert into orders(branch_id,shift_id,customer_id,table_id,order_type,status,kitchen_status,total,discount,tax,grand_total,created_by,notes)
 values(v_branch,p_shift_id,p_customer_id,p_table_id,p_order_type,case when p_draft then 'Draft' else 'Placed' end,case when p_draft then 'Pending' else 'Processing' end,
 v_subtotal,greatest(0,coalesce(p_discount,0)),greatest(0,coalesce(p_tax,0)),greatest(0,v_subtotal-greatest(0,coalesce(p_discount,0))+greatest(0,coalesce(p_tax,0))),public.nexa_my_user_id(),p_notes)
 returning id into v_order;
 for v_item in select * from jsonb_array_elements(p_items) loop
   v_variant:=nullif(v_item->>'variant_id','')::uuid; v_qty:=greatest(0.001,coalesce((v_item->>'qty')::numeric,1));
   select mv.price,mi.name,mi.id into v_price,v_name,v_product from menu_variants mv join menu_items mi on mi.id=mv.item_id where mv.id=v_variant and mi.branch_id=v_branch;
   insert into order_items(order_id,item_id,variant_id,name,qty,unit_price,status,notes) values(v_order,v_product,v_variant,v_name,v_qty,v_price,'Pending',nullif(v_item->>'notes',''));
 end loop;
 if not p_draft then perform public.nexa_queue_kitchen_order(v_order); end if;
 insert into audit_log(branch_id,actor_id,action,entity_type,entity_id,metadata) values(v_branch,public.nexa_my_user_id(),'ORDER_CREATED','order',v_order,jsonb_build_object('source',p_order_type,'total',v_subtotal));
 return v_order;
end $$;
grant execute on function public.nexa_create_order(text,uuid,uuid,uuid,jsonb,numeric,numeric,text,boolean) to authenticated;

-- Atomic payment: locks the order, prevents over-payment and enforces payment role on the server.
create or replace function public.nexa_pay_order(p_order_id uuid,p_payments jsonb)
returns void language plpgsql security definer set search_path=public as $$
declare v_order orders%rowtype;v_role text:=public.nexa_my_role();v_paid numeric;v_new numeric:=0;v jsonb;
begin
 if v_role not in ('Admin','Manager','Cashier') then raise exception 'Your role cannot receive payment'; end if;
 select * into v_order from orders where id=p_order_id and branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Order not found'; end if;
 if lower(coalesce(v_order.status,''))='cancelled' then raise exception 'Cancelled orders cannot be paid'; end if;
 select coalesce(sum(amount),0) into v_paid from payments where order_id=p_order_id and reversed_at is null and lower(coalesce(status,'paid'))='paid';
 for v in select * from jsonb_array_elements(coalesce(p_payments,'[]'::jsonb)) loop
   if coalesce((v->>'amount')::numeric,0)>0 then v_new:=v_new+(v->>'amount')::numeric; end if;
 end loop;
 if v_new<=0 then raise exception 'Enter payment amount'; end if;
 if v_paid+v_new>v_order.grand_total+0.01 then raise exception 'Payment exceeds order total'; end if;
 for v in select * from jsonb_array_elements(p_payments) loop
   if coalesce((v->>'amount')::numeric,0)>0 then insert into payments(order_id,method,amount,status,received_by) values(p_order_id,coalesce(nullif(v->>'method',''),'Cash'),(v->>'amount')::numeric,'Paid',public.nexa_my_user_id()); end if;
 end loop;
 if v_paid+v_new>=v_order.grand_total-0.01 then update orders set status='Completed',completed_at=now() where id=p_order_id; end if;
 insert into audit_log(branch_id,actor_id,action,entity_type,entity_id,metadata) values(v_order.branch_id,public.nexa_my_user_id(),'PAYMENT_RECEIVED','order',p_order_id,jsonb_build_object('amount',v_new));
end $$;
grant execute on function public.nexa_pay_order(uuid,jsonb) to authenticated;

-- Rider GPS is self-only, branch-bound and throttled to avoid needless writes.
create or replace function public.nexa_rider_push_location(p_rider_id uuid,p_lat numeric,p_lng numeric,p_accuracy_m numeric default null)
returns boolean language plpgsql security definer set search_path=public as $$
declare v_branch uuid;v_last rider_locations%rowtype;v_distance numeric;
begin
 if p_lat not between -90 and 90 or p_lng not between -180 and 180 then raise exception 'Invalid GPS coordinates'; end if;
 select branch_id into v_branch from riders where id=p_rider_id and profile_id=auth.uid() and on_duty=true;
 if v_branch is null then raise exception 'No active rider shift'; end if;
 select * into v_last from rider_locations where rider_id=p_rider_id order by recorded_at desc limit 1;
 if v_last.id is not null then
   v_distance:=public.nexa_distance_m(v_last.latitude,v_last.longitude,p_lat,p_lng);
   if v_last.recorded_at>now()-interval '20 seconds' and v_distance<25 then return false; end if;
 end if;
 insert into rider_locations(rider_id,branch_id,latitude,longitude,accuracy_m) values(p_rider_id,v_branch,p_lat,p_lng,p_accuracy_m);
 return true;
end $$;
grant execute on function public.nexa_rider_push_location(uuid,numeric,numeric,numeric) to authenticated;

-- Riders may update only their own assigned delivery through this function.
create or replace function public.nexa_rider_delivery_status(p_delivery_id uuid,p_status text)
returns void language plpgsql security definer set search_path=public as $$
declare v_delivery deliveries%rowtype;v_rider uuid;v_allowed text[]:=array['Assigned','Accepted','Picked Up','Rider Out','On the way','Arriving','Delivered','Problem'];
begin
 select id into v_rider from riders where profile_id=auth.uid() and on_duty=true;
 if v_rider is null then raise exception 'No active rider shift'; end if;
 select * into v_delivery from deliveries where id=p_delivery_id and rider_id=v_rider for update;
 if not found then raise exception 'Delivery is not assigned to you'; end if;
 if not (p_status=any(v_allowed)) then raise exception 'Invalid delivery status'; end if;
 update deliveries set status=p_status,handed_over_at=case when p_status in('Picked Up','Rider Out','On the way') then coalesce(handed_over_at,now()) else handed_over_at end,delivered_at=case when p_status='Delivered' then now() else delivered_at end where id=p_delivery_id;
 update orders set delivery_status=p_status,status=case when p_status='Delivered' then 'Delivered' else status end where id=v_delivery.order_id;
 insert into audit_log(branch_id,actor_id,action,entity_type,entity_id,metadata) values(v_delivery.branch_id,public.nexa_my_user_id(),'RIDER_DELIVERY_STATUS','delivery',p_delivery_id,jsonb_build_object('status',p_status));
end $$;
grant execute on function public.nexa_rider_delivery_status(uuid,text) to authenticated;

-- Immutable audit trail for ordinary authenticated users.
revoke update,delete on public.audit_log from authenticated;

create index if not exists payments_order_active_idx on public.payments(order_id,created_at desc) where reversed_at is null;
create index if not exists orders_branch_created_source_idx on public.orders(branch_id,created_at desc,order_type);
create index if not exists rider_locations_branch_time_idx on public.rider_locations(branch_id,recorded_at desc);
