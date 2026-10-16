-- NEXA Phase 9: restaurant role model + Admin-only paid -> unpaid reversal
insert into public.roles(name) values
 ('Admin'),('Manager'),('Cashier'),('Call Center'),('Dispatcher'),('Delivery Boy'),('Order Taker')
on conflict(name) do nothing;

-- Keep older names compatible with existing accounts while new users use the names above.
create or replace function public.nexa_my_role() returns text language sql stable security definer set search_path=public as $$
 select case lower(coalesce((select r.name from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id limit 1),u.role,'Cashier'))
   when 'rider' then 'Delivery Boy'
   when 'waiter' then 'Order Taker'
   when 'despature' then 'Dispatcher'
   when 'despatcher' then 'Dispatcher'
   else coalesce((select r.name from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id limit 1),u.role,'Cashier') end
 from public.users u where u.auth_id=auth.uid() limit 1
$$;

create or replace function public.nexa_is_management() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(public.nexa_my_role() in ('Admin','Manager'),false)
$$;

grant execute on function public.nexa_my_role(),public.nexa_is_management() to authenticated;

create or replace function public.nexa_admin_mark_order_unpaid(p_order_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_count integer:=0;
begin
 if public.nexa_my_role()<>'Admin' then raise exception 'Only Admin can reverse a paid order to unpaid'; end if;
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reversal reason is required'; end if;
 select * into v_order from public.orders where id=p_order_id and branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Order not found'; end if;
 update public.payments set reversed_at=now(),reversal_reason=p_reason,reversed_by=public.nexa_my_user_id(),status='Reversed'
 where order_id=p_order_id and reversed_at is null and lower(coalesce(status,'paid'))<>'reversed';
 get diagnostics v_count = row_count;
 if v_count=0 then raise exception 'This order has no active paid payment to reverse'; end if;
 update public.orders set status='Placed',completed_at=null,updated_at=now() where id=p_order_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_order.branch_id,public.nexa_my_user_id(),'ORDER_MARKED_UNPAID','order',p_order_id,p_reason,jsonb_build_object('reversed_payments',v_count,'grand_total',v_order.grand_total));
end $$;
grant execute on function public.nexa_admin_mark_order_unpaid(uuid,text) to authenticated;

-- Enforce payment permission in the database, not only in React.
drop policy if exists "p3 payments insert" on public.payments;
create policy "p9 payments insert by role" on public.payments for insert to authenticated
with check(public.nexa_my_role() in ('Admin','Manager','Cashier','Call Center','Dispatcher') and exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch()));

-- Order entry is available to front-counter/order-entry roles. Delivery Boy cannot punch orders.
drop policy if exists "p3 orders insert" on public.orders;
drop policy if exists "branch orders insert" on public.orders;
create policy "p9 orders insert by role" on public.orders for insert to authenticated
with check(branch_id=public.nexa_my_branch() and public.nexa_my_role() in ('Admin','Manager','Cashier','Call Center','Dispatcher','Order Taker'));

-- Dispatcher/Admin/Manager only: rider assignment.
create or replace function public.nexa_assign_rider(p_delivery_id uuid,p_rider_id uuid)
returns void language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=public.nexa_my_branch();
begin
 if public.nexa_my_role() not in ('Admin','Manager','Dispatcher') then raise exception 'Your role cannot assign orders to riders'; end if;
 if not exists(select 1 from public.deliveries where id=p_delivery_id and branch_id=v_branch) then raise exception 'Delivery not found'; end if;
 if not exists(select 1 from public.riders where id=p_rider_id and branch_id=v_branch and on_duty=true) then raise exception 'Rider is not available'; end if;
 update public.deliveries set rider_id=p_rider_id,status='Assigned',assigned_at=now() where id=p_delivery_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,metadata)
 values(v_branch,public.nexa_my_user_id(),'RIDER_ASSIGNED','delivery',p_delivery_id,jsonb_build_object('rider_id',p_rider_id));
end $$;
grant execute on function public.nexa_assign_rider(uuid,uuid) to authenticated;

-- Profit is a server-side Admin-only value. Other roles receive nulls even if they call the RPC manually.
create or replace function public.nexa_finance_dashboard(p_start date,p_end date)
returns table(gross_sales numeric,discounts numeric,tax numeric,net_sales numeric,orders bigint,collected numeric,due_amount numeric,expenses numeric,purchases numeric,cogs numeric,wastage numeric,gross_profit numeric,gross_margin numeric,net_profit numeric)
language sql stable security definer set search_path=public as $$
with o as (
 select coalesce(sum(total),0) gross_sales,coalesce(sum(discount),0) discounts,coalesce(sum(tax),0) tax,coalesce(sum(grand_total),0) net_sales,count(*) orders
 from orders where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), p as (
 select coalesce(sum(case when p.reversed_at is null and lower(coalesce(p.status,'')) not in ('reversed','cancelled') then p.amount else 0 end),0) collected
 from payments p join orders o2 on o2.id=p.order_id where o2.branch_id=nexa_my_branch() and p.created_at>=p_start::timestamptz and p.created_at<(p_end+1)::timestamptz
), e as (select coalesce(sum(amount),0) expenses from expenses where branch_id=nexa_my_branch() and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz),
pu as (select coalesce(sum(total),0) purchases from purchases where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','rejected') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz),
c as (select coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('sale','consumption','recipe_consumption','order_consumption','stock_out')),0) cogs,coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('wastage','waste')),0) wastage from stock_movements sm left join ingredients i on i.id=sm.ingredient_id where sm.branch_id=nexa_my_branch() and sm.created_at>=p_start::timestamptz and sm.created_at<(p_end+1)::timestamptz)
select o.gross_sales,o.discounts,o.tax,o.net_sales,o.orders,p.collected,greatest(o.net_sales-p.collected,0),e.expenses,pu.purchases,
 case when nexa_my_role()='Admin' then c.cogs else null end,
 case when nexa_my_role()='Admin' then c.wastage else null end,
 case when nexa_my_role()='Admin' then (o.net_sales-o.tax-c.cogs) else null end,
 case when nexa_my_role()='Admin' then (case when o.net_sales-o.tax=0 then 0 else ((o.net_sales-o.tax-c.cogs)/(o.net_sales-o.tax))*100 end) else null end,
 case when nexa_my_role()='Admin' then (o.net_sales-o.tax-c.cogs-e.expenses-c.wastage) else null end
from o,p,e,pu,c;
$$;

create or replace function public.nexa_profit_loss(p_start date,p_end date)
returns table(metric text,amount numeric) language plpgsql stable security definer set search_path=public as $$
begin
 if public.nexa_my_role()<>'Admin' then raise exception 'Profit & Loss is available to Admin only'; end if;
 return query with d as (select * from nexa_finance_dashboard(p_start,p_end))
 select 'Net Sales'::text,net_sales from d union all select 'Less: Tax / VAT',-tax from d union all select 'Less: Cost of Goods Sold',-cogs from d union all select 'Gross Profit',gross_profit from d union all select 'Less: Operating Expenses',-expenses from d union all select 'Less: Wastage',-wastage from d union all select 'Estimated Net Profit',net_profit from d;
end $$;
