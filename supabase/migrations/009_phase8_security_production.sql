-- NEXA Phase 8: security, privileged actions, audit trail and production safeguards
-- Run after the corrected 008 migration.
create extension if not exists pgcrypto;

create or replace function public.nexa_my_user_id() returns uuid language sql stable security definer set search_path=public as $$
 select id from public.users where auth_id=auth.uid() limit 1
$$;
create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$
 select branch_id from public.users where auth_id=auth.uid() limit 1
$$;
create or replace function public.nexa_my_role() returns text language sql stable security definer set search_path=public as $$
 select coalesce((select r.name from public.user_roles ur join public.roles r on r.id=ur.role_id where ur.user_id=u.id limit 1),u.role,'Cashier') from public.users u where u.auth_id=auth.uid() limit 1
$$;
create or replace function public.nexa_is_management() returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(public.nexa_my_role() in ('Developer','Admin','Manager'),false)
$$;
grant execute on function public.nexa_my_user_id(),public.nexa_my_branch(),public.nexa_my_role(),public.nexa_is_management() to authenticated;

-- Normalize the audit table regardless of which early schema created it first.
alter table public.audit_log add column if not exists actor_id uuid;
alter table public.audit_log add column if not exists metadata jsonb default '{}'::jsonb;
alter table public.manager_authorizations add column if not exists branch_id uuid;
alter table public.manager_authorizations add column if not exists requested_by uuid;
alter table public.manager_authorizations add column if not exists authorized_by uuid;
alter table public.manager_authorizations add column if not exists action text;
alter table public.manager_authorizations add column if not exists entity_type text;
alter table public.manager_authorizations add column if not exists entity_id uuid;
alter table public.manager_authorizations add column if not exists reason text;
alter table public.manager_authorizations add column if not exists created_at timestamptz default now();
alter table public.payments add column if not exists reversed_by uuid;

create or replace function public.nexa_authorize_manager_pin(p_pin text,p_action text,p_entity_type text default null,p_entity_id uuid default null,p_reason text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_authorizer uuid; v_id uuid; v_branch uuid:=public.nexa_my_branch();
begin
 if coalesce(trim(p_pin),'')='' then raise exception 'Manager PIN is required'; end if;
 select u.id into v_authorizer from public.users u
 where u.branch_id=v_branch and coalesce(u.status,'Active')='Active' and coalesce(u.role,public.nexa_my_role()) in ('Developer','Admin','Manager')
   and u.pin_hash is not null and crypt(p_pin,u.pin_hash)=u.pin_hash
 limit 1;
 if v_authorizer is null then raise exception 'Invalid manager authorization PIN'; end if;
 insert into public.manager_authorizations(branch_id,requested_by,authorized_by,action,entity_type,entity_id,reason)
 values(v_branch,public.nexa_my_user_id(),v_authorizer,p_action,p_entity_type,p_entity_id,p_reason) returning id into v_id;
 return v_id;
end $$;
grant execute on function public.nexa_authorize_manager_pin(text,text,text,uuid,text) to authenticated;

create or replace function public.nexa_secure_cancel_order(p_order_id uuid,p_reason text,p_manager_pin text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_role text:=public.nexa_my_role();
begin
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Cancellation reason is required'; end if;
 select * into v_order from public.orders where id=p_order_id and branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Order not found'; end if;
 if lower(coalesce(v_order.status,''))='cancelled' then raise exception 'Order is already cancelled'; end if;
 if v_role not in ('Developer','Admin','Manager') then perform public.nexa_authorize_manager_pin(p_manager_pin,'ORDER_CANCEL','order',p_order_id,p_reason); end if;
 update public.orders set status='Cancelled',cancel_reason=p_reason,updated_at=now() where id=p_order_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_order.branch_id,public.nexa_my_user_id(),'ORDER_CANCELLED','order',p_order_id,p_reason,jsonb_build_object('previous_status',v_order.status,'grand_total',v_order.grand_total));
end $$;
grant execute on function public.nexa_secure_cancel_order(uuid,text,text) to authenticated;

create or replace function public.nexa_reverse_payment(p_payment_id uuid,p_reason text,p_manager_pin text)
returns void language plpgsql security definer set search_path=public as $$
declare v_payment public.payments%rowtype; v_order public.orders%rowtype;
begin
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Reversal reason is required'; end if;
 select p.* into v_payment from public.payments p join public.orders o on o.id=p.order_id where p.id=p_payment_id and o.branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Payment not found'; end if;
 if v_payment.reversed_at is not null then raise exception 'Payment is already reversed'; end if;
 perform public.nexa_authorize_manager_pin(p_manager_pin,'PAYMENT_REVERSE','payment',p_payment_id,p_reason);
 update public.payments set reversed_at=now(),reversal_reason=p_reason,reversed_by=public.nexa_my_user_id(),status='Reversed' where id=p_payment_id;
 select * into v_order from public.orders where id=v_payment.order_id;
 update public.orders set status='Placed',completed_at=null,updated_at=now() where id=v_payment.order_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_order.branch_id,public.nexa_my_user_id(),'PAYMENT_REVERSED','payment',p_payment_id,p_reason,jsonb_build_object('order_id',v_payment.order_id,'amount',v_payment.amount,'method',v_payment.method));
end $$;
grant execute on function public.nexa_reverse_payment(uuid,text,text) to authenticated;

create or replace function public.nexa_secure_close_shift(p_shift_id uuid,p_actual_cash numeric,p_manager_pin text,p_note text default null)
returns void language plpgsql security definer set search_path=public as $$
declare v_shift public.shifts%rowtype; v_pending bigint; v_cash numeric:=0; v_in numeric:=0; v_out numeric:=0; v_exp numeric:=0; v_expected numeric:=0;
begin
 select * into v_shift from public.shifts where id=p_shift_id and branch_id=public.nexa_my_branch() for update;
 if not found then raise exception 'Shift not found'; end if;
 if lower(coalesce(v_shift.status,''))='closed' then raise exception 'Shift is already closed'; end if;
 perform public.nexa_authorize_manager_pin(p_manager_pin,'SHIFT_CLOSE','shift',p_shift_id,p_note);
 select count(*) into v_pending from public.orders where shift_id=p_shift_id and lower(coalesce(status,'')) not in ('completed','cancelled');
 if v_pending>0 then raise exception 'Cannot close shift: % pending order(s) remain',v_pending; end if;
 select coalesce(sum(p.amount),0) into v_cash from public.payments p join public.orders o on o.id=p.order_id where o.shift_id=p_shift_id and lower(p.method)='cash' and p.reversed_at is null;
 select coalesce(sum(amount),0) into v_in from public.cash_movements where shift_id=p_shift_id and lower(type) in ('cash_in','in');
 select coalesce(sum(amount),0) into v_out from public.cash_movements where shift_id=p_shift_id and lower(type) in ('cash_out','out');
 select coalesce(sum(amount),0) into v_exp from public.expenses where shift_id=p_shift_id;
 v_expected:=coalesce(v_shift.opening_cash,0)+v_cash+v_in-v_out-v_exp;
 update public.shifts set status='Closed',closed_at=now(),closed_by=auth.uid(),expected_cash=v_expected,actual_cash=p_actual_cash where id=p_shift_id;
 insert into public.audit_log(branch_id,actor_id,action,entity_type,entity_id,reason,metadata)
 values(v_shift.branch_id,public.nexa_my_user_id(),'SHIFT_CLOSED','shift',p_shift_id,p_note,jsonb_build_object('expected_cash',v_expected,'actual_cash',p_actual_cash,'difference',p_actual_cash-v_expected));
end $$;
grant execute on function public.nexa_secure_close_shift(uuid,numeric,text,text) to authenticated;

-- Remove the permissive Phase 2 policies from sensitive tables.
do $$ declare t text; begin
 foreach t in array array['manager_authorizations','shifts','cash_movements','expenses','audit_log'] loop
   if to_regclass('public.'||t) is not null then
     execute format('alter table public.%I enable row level security',t);
     execute format('drop policy if exists authenticated_all on public.%I',t);
   end if;
 end loop;
end $$;

-- Branch-scoped read/write policies. Privileged mutations should use the RPCs above.
drop policy if exists p8_shifts_read on public.shifts;
create policy p8_shifts_read on public.shifts for select to authenticated using(branch_id=public.nexa_my_branch());
drop policy if exists p8_shifts_insert on public.shifts;
create policy p8_shifts_insert on public.shifts for insert to authenticated with check(branch_id=public.nexa_my_branch() and public.nexa_is_management());
drop policy if exists p8_cash_branch on public.cash_movements;
create policy p8_cash_branch on public.cash_movements for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch());
drop policy if exists p8_expenses_branch on public.expenses;
create policy p8_expenses_branch on public.expenses for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch());
drop policy if exists p8_audit_read on public.audit_log;
create policy p8_audit_read on public.audit_log for select to authenticated using(branch_id=public.nexa_my_branch() and public.nexa_is_management());
drop policy if exists p8_auth_read on public.manager_authorizations;
create policy p8_auth_read on public.manager_authorizations for select to authenticated using(branch_id=public.nexa_my_branch() and public.nexa_is_management());

-- Prevent negative ingredient stock even when a client attempts a direct update.
create or replace function public.nexa_prevent_negative_stock() returns trigger language plpgsql as $$ begin
 if new.quantity<0 then raise exception 'Negative stock is not allowed for %',new.name; end if; return new; end $$;
drop trigger if exists trg_nexa_no_negative_stock on public.ingredients;
create trigger trg_nexa_no_negative_stock before insert or update of quantity on public.ingredients for each row execute function public.nexa_prevent_negative_stock();

create index if not exists idx_audit_branch_created on public.audit_log(branch_id,created_at desc);
create index if not exists idx_manager_auth_branch_created on public.manager_authorizations(branch_id,created_at desc);
