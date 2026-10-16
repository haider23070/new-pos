-- NEXA Phase 11: menu departments, printer routing, per-user receipt printers and staff access
alter table public.menu_items add column if not exists department_id uuid references public.kitchen_departments(id) on delete set null;
alter table public.print_jobs add column if not exists department_id uuid references public.kitchen_departments(id) on delete set null;
alter table public.print_jobs add column if not exists payload jsonb not null default '{}'::jsonb;
alter table public.profiles add column if not exists receipt_printer_name text;
alter table public.profiles add column if not exists theme text default 'dark';

do $$ begin
 alter table public.profiles add constraint profiles_theme_check check(theme in ('dark','light','system'));
exception when duplicate_object then null; end $$;

-- Management can maintain menu, variants, departments and printers for its own branch.
do $$ begin create policy "p11 menu management" on public.menu_items for all to authenticated
 using(branch_id=public.nexa_my_branch() and public.nexa_my_role() in ('Admin','Manager'))
 with check(branch_id=public.nexa_my_branch() and public.nexa_my_role() in ('Admin','Manager'));
exception when duplicate_object then null; end $$;
do $$ begin create policy "p11 category management" on public.categories for all to authenticated
 using(branch_id=public.nexa_my_branch() and public.nexa_my_role() in ('Admin','Manager'))
 with check(branch_id=public.nexa_my_branch() and public.nexa_my_role() in ('Admin','Manager'));
exception when duplicate_object then null; end $$;
do $$ begin create policy "p11 variant management" on public.menu_variants for all to authenticated
 using(exists(select 1 from public.menu_items m where m.id=item_id and m.branch_id=public.nexa_my_branch()) and public.nexa_my_role() in ('Admin','Manager'))
 with check(exists(select 1 from public.menu_items m where m.id=item_id and m.branch_id=public.nexa_my_branch()) and public.nexa_my_role() in ('Admin','Manager'));
exception when duplicate_object then null; end $$;

create or replace function public.nexa_queue_kitchen_order(p_order_id uuid)
returns integer language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_count integer:=0; rec record; v_printer text;
begin
 select * into v_order from public.orders where id=p_order_id and branch_id=public.nexa_my_branch();
 if not found then raise exception 'Order not found'; end if;
 if lower(coalesce(v_order.status,''))='draft' then return 0; end if;
 for rec in
   select m.department_id, jsonb_agg(jsonb_build_object('name',oi.name,'qty',oi.qty,'notes',oi.notes) order by oi.name) items
   from public.order_items oi left join public.menu_items m on m.id=oi.item_id
   where oi.order_id=p_order_id group by m.department_id
 loop
   select ps.printer_name into v_printer from public.printer_settings ps
   where ps.branch_id=v_order.branch_id and ps.department_id is not distinct from rec.department_id and ps.active=true and ps.auto_print=true
   order by ps.created_at limit 1;
   if v_printer is not null then
     insert into public.print_jobs(branch_id,order_id,job_type,printer_name,status,created_by,department_id,payload)
     values(v_order.branch_id,p_order_id,'KOT',v_printer,'Queued',auth.uid(),rec.department_id,
       jsonb_build_object('token',v_order.token,'order_type',v_order.order_type,'notes',v_order.notes,'items',rec.items));
     v_count:=v_count+1;
   end if;
 end loop;
 return v_count;
end $$;
grant execute on function public.nexa_queue_kitchen_order(uuid) to authenticated;

create or replace function public.nexa_queue_receipt(p_order_id uuid)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_order public.orders%rowtype; v_printer text; v_id uuid; v_items jsonb;
begin
 select * into v_order from public.orders where id=p_order_id and branch_id=public.nexa_my_branch();
 if not found then raise exception 'Order not found'; end if;
 select receipt_printer_name into v_printer from public.profiles where id=auth.uid();
 if coalesce(trim(v_printer),'')='' then raise exception 'Select your bill printer in Settings first'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('name',name,'qty',qty,'unit_price',unit_price) order by name),'[]'::jsonb) into v_items from public.order_items where order_id=p_order_id;
 insert into public.print_jobs(branch_id,order_id,job_type,printer_name,status,created_by,payload)
 values(v_order.branch_id,p_order_id,'RECEIPT',v_printer,'Queued',auth.uid(),jsonb_build_object('token',v_order.token,'order_type',v_order.order_type,'total',v_order.grand_total,'items',v_items)) returning id into v_id;
 return v_id;
end $$;
grant execute on function public.nexa_queue_receipt(uuid) to authenticated;
-- Call Center and Dispatcher must never receive POS payment.
drop policy if exists "p9 payments insert by role" on public.payments;
create policy "p11 payments insert by role" on public.payments for insert to authenticated
with check(public.nexa_my_role() in ('Admin','Manager','Cashier') and exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch()));
insert into public.roles(name) values ('Kitchen Staff') on conflict(name) do nothing;
