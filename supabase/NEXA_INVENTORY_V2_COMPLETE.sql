-- NEXA Inventory v2 migration. Run AFTER NEXA_INVENTORY_SYSTEM.sql.
create extension if not exists pgcrypto;

create table if not exists public.inventory_departments(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade,
 name text not null, active boolean not null default true, created_at timestamptz not null default now(), unique(branch_id,name));
create table if not exists public.inventory_locations(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade,
 department_id uuid references public.inventory_departments(id) on delete set null, name text not null, type text not null default 'STORE', active boolean not null default true,
 created_at timestamptz not null default now(), unique(branch_id,name));
create table if not exists public.inventory_location_stock(
 location_id uuid not null references public.inventory_locations(id) on delete cascade, ingredient_id uuid not null references public.inventory_ingredients(id) on delete cascade,
 quantity numeric(14,3) not null default 0, avg_cost numeric(14,4) not null default 0, updated_at timestamptz not null default now(), primary key(location_id,ingredient_id));

create table if not exists public.inventory_purchase_orders(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade, supplier_id uuid references public.inventory_suppliers(id),
 po_no text, status text not null default 'DRAFT' check(status in('DRAFT','PENDING','APPROVED','PARTIALLY_RECEIVED','RECEIVED','REJECTED','CANCELLED')),
 expected_date date, notes text, total_amount numeric(14,2) not null default 0, created_by uuid, approved_by uuid, approved_at timestamptz, created_at timestamptz not null default now());
create table if not exists public.inventory_purchase_order_items(
 id uuid primary key default gen_random_uuid(), purchase_order_id uuid not null references public.inventory_purchase_orders(id) on delete cascade,
 ingredient_id uuid not null references public.inventory_ingredients(id), quantity numeric(14,3) not null check(quantity>0), received_qty numeric(14,3) not null default 0,
 unit_cost numeric(14,4) not null default 0, total numeric(14,2) generated always as(quantity*unit_cost) stored);

create table if not exists public.inventory_purchase_returns(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade, purchase_id uuid references public.inventory_purchases(id),
 supplier_id uuid references public.inventory_suppliers(id), return_no text, reason text, total_amount numeric(14,2) not null default 0, status text not null default 'POSTED', created_by uuid, created_at timestamptz not null default now());
create table if not exists public.inventory_purchase_return_items(
 id uuid primary key default gen_random_uuid(), return_id uuid not null references public.inventory_purchase_returns(id) on delete cascade, ingredient_id uuid not null references public.inventory_ingredients(id),
 quantity numeric(14,3) not null check(quantity>0), unit_cost numeric(14,4) not null default 0, total numeric(14,2) generated always as(quantity*unit_cost) stored);

create table if not exists public.inventory_requests(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade,
 request_type text not null check(request_type in('TRANSFER','ISSUANCE')), from_location_id uuid references public.inventory_locations(id), to_location_id uuid references public.inventory_locations(id),
 status text not null default 'PENDING' check(status in('DRAFT','PENDING','APPROVED','PARTIALLY_FULFILLED','FULFILLED','REJECTED','CANCELLED')),
 notes text, created_by uuid, approved_by uuid, approved_at timestamptz, created_at timestamptz not null default now());
create table if not exists public.inventory_request_items(
 id uuid primary key default gen_random_uuid(), request_id uuid not null references public.inventory_requests(id) on delete cascade, ingredient_id uuid not null references public.inventory_ingredients(id),
 requested_qty numeric(14,3) not null check(requested_qty>0), fulfilled_qty numeric(14,3) not null default 0);

create table if not exists public.inventory_transfers(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade, request_id uuid references public.inventory_requests(id),
 from_location_id uuid references public.inventory_locations(id), to_location_id uuid references public.inventory_locations(id), status text not null default 'POSTED', notes text, created_by uuid, created_at timestamptz not null default now());
create table if not exists public.inventory_transfer_items(
 id uuid primary key default gen_random_uuid(), transfer_id uuid not null references public.inventory_transfers(id) on delete cascade, ingredient_id uuid not null references public.inventory_ingredients(id), quantity numeric(14,3) not null check(quantity>0));

create table if not exists public.inventory_recipe_groups(id uuid primary key default gen_random_uuid(),branch_id uuid not null references public.pos_branches(id) on delete cascade,name text not null,active boolean default true,unique(branch_id,name));
alter table public.inventory_recipes add column if not exists group_id uuid references public.inventory_recipe_groups(id) on delete set null;
alter table public.inventory_recipes add column if not exists version integer not null default 1;
alter table public.inventory_recipes add column if not exists notes text;

create table if not exists public.inventory_productions(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade, department_id uuid references public.inventory_departments(id),
 recipe_id uuid references public.inventory_recipes(id), production_type text not null default 'FOOD', quantity numeric(14,3) not null check(quantity>0), notes text, created_by uuid, created_at timestamptz not null default now());

create table if not exists public.inventory_batches(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade, ingredient_id uuid not null references public.inventory_ingredients(id),
 batch_no text, expiry_date date, quantity numeric(14,3) not null default 0, unit_cost numeric(14,4) not null default 0, source_type text, source_id uuid, created_at timestamptz not null default now());
create index if not exists inventory_batches_expiry on public.inventory_batches(branch_id,expiry_date);

create table if not exists public.inventory_direct_sales(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade, sale_no text, customer_name text,
 total_amount numeric(14,2) not null default 0, notes text, created_by uuid, created_at timestamptz not null default now());
create table if not exists public.inventory_direct_sale_items(
 id uuid primary key default gen_random_uuid(), sale_id uuid not null references public.inventory_direct_sales(id) on delete cascade, ingredient_id uuid not null references public.inventory_ingredients(id),
 quantity numeric(14,3) not null check(quantity>0), unit_price numeric(14,4) not null check(unit_price>=0), total numeric(14,2) generated always as(quantity*unit_price) stored);

create table if not exists public.inventory_cost_history(
 id uuid primary key default gen_random_uuid(), branch_id uuid not null references public.pos_branches(id) on delete cascade, ingredient_id uuid not null references public.inventory_ingredients(id),
 old_cost numeric(14,4) not null, new_cost numeric(14,4) not null, source_type text, source_id uuid, created_at timestamptz not null default now());

-- supplier ledger view: purchases debit supplier, returns/payments credit supplier
create or replace view public.inventory_supplier_ledger as
 select p.branch_id,p.supplier_id,p.created_at,'PURCHASE'::text entry_type,p.id reference_id,p.invoice_no reference_no,p.total_amount debit,0::numeric credit,p.notes
 from inventory_purchases p where p.supplier_id is not null
 union all select r.branch_id,r.supplier_id,r.created_at,'PURCHASE_RETURN',r.id,r.return_no,0,r.total_amount,r.reason from inventory_purchase_returns r where r.supplier_id is not null
 union all select x.branch_id,x.supplier_id,x.created_at,'PAYMENT',x.id,null,0,x.amount,x.notes from inventory_supplier_payments x;

create or replace function public.nexa_inventory_create_po(p_branch_id uuid,p_supplier_id uuid,p_po_no text,p_expected_date date,p_notes text,p_lines jsonb,p_user_id uuid default auth.uid()) returns uuid
language plpgsql security definer set search_path=public as $$declare v_id uuid;v jsonb;v_total numeric:=0;begin
 if jsonb_array_length(coalesce(p_lines,'[]'::jsonb))=0 then raise exception 'Add at least one item';end if;
 insert into inventory_purchase_orders(branch_id,supplier_id,po_no,expected_date,notes,status,created_by) values(p_branch_id,p_supplier_id,p_po_no,p_expected_date,p_notes,'PENDING',p_user_id) returning id into v_id;
 for v in select * from jsonb_array_elements(p_lines) loop insert into inventory_purchase_order_items(purchase_order_id,ingredient_id,quantity,unit_cost) values(v_id,(v->>'ingredient_id')::uuid,(v->>'quantity')::numeric,coalesce((v->>'unit_cost')::numeric,0));v_total:=v_total+(v->>'quantity')::numeric*coalesce((v->>'unit_cost')::numeric,0);end loop;
 update inventory_purchase_orders set total_amount=v_total where id=v_id;return v_id;end$$;

create or replace function public.nexa_inventory_po_action(p_po_id uuid,p_action text,p_user_id uuid default auth.uid()) returns text language plpgsql security definer set search_path=public as $$begin
 if upper(p_action)='APPROVE' then update inventory_purchase_orders set status='APPROVED',approved_by=p_user_id,approved_at=now() where id=p_po_id and status='PENDING';
 elsif upper(p_action)='REJECT' then update inventory_purchase_orders set status='REJECTED' where id=p_po_id and status in('PENDING','DRAFT');
 elsif upper(p_action)='CANCEL' then update inventory_purchase_orders set status='CANCELLED' where id=p_po_id and status not in('RECEIVED','CANCELLED'); else raise exception 'Invalid action'; end if;return 'OK';end$$;

create or replace function public.nexa_inventory_purchase_return(p_branch_id uuid,p_purchase_id uuid,p_supplier_id uuid,p_return_no text,p_reason text,p_lines jsonb,p_user_id uuid default auth.uid()) returns uuid language plpgsql security definer set search_path=public as $$declare v_id uuid;v jsonb;v_total numeric:=0;begin
 insert into inventory_purchase_returns(branch_id,purchase_id,supplier_id,return_no,reason,created_by) values(p_branch_id,p_purchase_id,p_supplier_id,p_return_no,p_reason,p_user_id) returning id into v_id;
 for v in select * from jsonb_array_elements(p_lines) loop insert into inventory_purchase_return_items(return_id,ingredient_id,quantity,unit_cost) values(v_id,(v->>'ingredient_id')::uuid,(v->>'quantity')::numeric,coalesce((v->>'unit_cost')::numeric,0));perform nexa_inventory_post_movement(p_branch_id,(v->>'ingredient_id')::uuid,'PURCHASE_RETURN',(v->>'quantity')::numeric,0,'PURCHASE_RETURN',v_id,p_reason,p_user_id);v_total:=v_total+(v->>'quantity')::numeric*coalesce((v->>'unit_cost')::numeric,0);end loop;update inventory_purchase_returns set total_amount=v_total where id=v_id;return v_id;end$$;

create or replace function public.nexa_inventory_create_request(p_branch_id uuid,p_request_type text,p_from_location uuid,p_to_location uuid,p_notes text,p_lines jsonb,p_user_id uuid default auth.uid()) returns uuid language plpgsql security definer set search_path=public as $$declare v_id uuid;v jsonb;begin
 insert into inventory_requests(branch_id,request_type,from_location_id,to_location_id,notes,created_by) values(p_branch_id,upper(p_request_type),p_from_location,p_to_location,p_notes,p_user_id) returning id into v_id;
 for v in select * from jsonb_array_elements(p_lines) loop insert into inventory_request_items(request_id,ingredient_id,requested_qty) values(v_id,(v->>'ingredient_id')::uuid,(v->>'quantity')::numeric);end loop;return v_id;end$$;

create or replace function public.nexa_inventory_request_action(p_request_id uuid,p_action text,p_user_id uuid default auth.uid()) returns text language plpgsql security definer set search_path=public as $$begin
 if upper(p_action)='APPROVE' then update inventory_requests set status='APPROVED',approved_by=p_user_id,approved_at=now() where id=p_request_id and status='PENDING';
 elsif upper(p_action)='REJECT' then update inventory_requests set status='REJECTED' where id=p_request_id and status='PENDING';
 elsif upper(p_action)='CANCEL' then update inventory_requests set status='CANCELLED' where id=p_request_id and status in('DRAFT','PENDING','APPROVED'); else raise exception 'Invalid action';end if;return 'OK';end$$;

create or replace function public.nexa_inventory_post_transfer(p_branch_id uuid,p_request_id uuid,p_from_location uuid,p_to_location uuid,p_notes text,p_lines jsonb,p_user_id uuid default auth.uid()) returns uuid language plpgsql security definer set search_path=public as $$declare v_id uuid;v jsonb;v_ing uuid;v_qty numeric;begin
 insert into inventory_transfers(branch_id,request_id,from_location_id,to_location_id,notes,created_by) values(p_branch_id,p_request_id,p_from_location,p_to_location,p_notes,p_user_id) returning id into v_id;
 for v in select * from jsonb_array_elements(p_lines) loop v_ing:=(v->>'ingredient_id')::uuid;v_qty:=(v->>'quantity')::numeric;insert into inventory_transfer_items(transfer_id,ingredient_id,quantity) values(v_id,v_ing,v_qty);perform nexa_inventory_post_movement(p_branch_id,v_ing,case when p_to_location is null then 'ISSUE' else 'TRANSFER_OUT' end,v_qty,0,'TRANSFER',v_id,p_notes,p_user_id);end loop;
 if p_request_id is not null then update inventory_requests set status='FULFILLED' where id=p_request_id;update inventory_request_items ri set fulfilled_qty=requested_qty where request_id=p_request_id;end if;return v_id;end$$;

create or replace function public.nexa_inventory_direct_sale(p_branch_id uuid,p_sale_no text,p_customer text,p_notes text,p_lines jsonb,p_user_id uuid default auth.uid()) returns uuid language plpgsql security definer set search_path=public as $$declare v_id uuid;v jsonb;v_total numeric:=0;begin
 insert into inventory_direct_sales(branch_id,sale_no,customer_name,notes,created_by) values(p_branch_id,p_sale_no,p_customer,p_notes,p_user_id) returning id into v_id;
 for v in select * from jsonb_array_elements(p_lines) loop insert into inventory_direct_sale_items(sale_id,ingredient_id,quantity,unit_price) values(v_id,(v->>'ingredient_id')::uuid,(v->>'quantity')::numeric,coalesce((v->>'unit_price')::numeric,0));perform nexa_inventory_post_movement(p_branch_id,(v->>'ingredient_id')::uuid,'DIRECT_SALE',(v->>'quantity')::numeric,0,'DIRECT_SALE',v_id,p_customer,p_user_id);v_total:=v_total+(v->>'quantity')::numeric*coalesce((v->>'unit_price')::numeric,0);end loop;update inventory_direct_sales set total_amount=v_total where id=v_id;return v_id;end$$;

create or replace function public.nexa_inventory_reverse_order_consumption(p_order_id uuid) returns integer language plpgsql security definer set search_path=public as $$declare r record;n int:=0;begin
 if exists(select 1 from inventory_movements where reference_type='ORDER_CONSUMPTION_REVERSAL' and reference_id=p_order_id) then return 0;end if;
 for r in select * from inventory_movements where reference_type='ORDER_CONSUMPTION' and reference_id=p_order_id loop perform nexa_inventory_post_movement(r.branch_id,r.ingredient_id,'RETURN_IN',abs(r.quantity),r.unit_cost,'ORDER_CONSUMPTION_REVERSAL',p_order_id,'Order cancellation/refund reversal',auth.uid());n:=n+1;end loop;return n;end$$;

create or replace view public.inventory_food_cost as select r.id recipe_id,r.branch_id,r.name,coalesce(sum(ri.quantity*(1+coalesce(ri.wastage_pct,0)/100)*i.avg_cost/nullif(r.yield_qty,0)),0) food_cost from inventory_recipes r left join inventory_recipe_items ri on ri.recipe_id=r.id left join inventory_ingredients i on i.id=ri.ingredient_id group by r.id,r.branch_id,r.name;
create or replace view public.inventory_low_stock as select *,greatest(min_qty-current_qty,0) suggested_qty from inventory_ingredients where active=true and current_qty<=min_qty;
create or replace view public.inventory_supplier_payable as select s.id supplier_id,s.branch_id,s.name,coalesce(s.opening_balance,0)+coalesce(sum(l.debit-l.credit),0) payable from inventory_suppliers s left join inventory_supplier_ledger l on l.supplier_id=s.id group by s.id,s.branch_id,s.name,s.opening_balance;

-- Secure all v2 tables for authenticated users. Existing NEXA role/branch policy can replace these permissive migration policies.
do $$declare t text;begin foreach t in array array['inventory_departments','inventory_locations','inventory_location_stock','inventory_purchase_orders','inventory_purchase_order_items','inventory_purchase_returns','inventory_purchase_return_items','inventory_requests','inventory_request_items','inventory_transfers','inventory_transfer_items','inventory_recipe_groups','inventory_productions','inventory_batches','inventory_direct_sales','inventory_direct_sale_items','inventory_cost_history'] loop execute format('alter table public.%I enable row level security',t);execute format('drop policy if exists nexa_inventory_v2_auth on public.%I',t);execute format('create policy nexa_inventory_v2_auth on public.%I for all to authenticated using(true) with check(true)',t);end loop;end$$;
grant select,insert,update,delete on all tables in schema public to authenticated;grant select on public.inventory_supplier_ledger,public.inventory_food_cost,public.inventory_low_stock,public.inventory_supplier_payable to authenticated;
grant execute on all functions in schema public to authenticated;

-- V2.1 completion: PO receiving and production posting
create or replace function public.nexa_inventory_receive_po(p_po_id uuid,p_user_id uuid default auth.uid()) returns uuid
language plpgsql security definer set search_path=public as $$
declare po record; li record; v_purchase uuid; v_lines jsonb;
begin
 select * into po from inventory_purchase_orders where id=p_po_id for update;
 if not found then raise exception 'Purchase order not found'; end if;
 if po.status<>'APPROVED' then raise exception 'Only APPROVED purchase orders can be received'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('ingredient_id',ingredient_id,'quantity',quantity,'unit_cost',unit_cost)),'[]'::jsonb) into v_lines from inventory_purchase_order_items where purchase_order_id=p_po_id;
 v_purchase:=nexa_inventory_create_purchase(po.branch_id,po.supplier_id,coalesce(po.po_no,'PO')||'-GRN','Received from purchase order',v_lines,p_user_id);
 update inventory_purchase_orders set status='RECEIVED',received_at=now() where id=p_po_id;
 return v_purchase;
end$$;

create or replace function public.nexa_inventory_post_production(p_branch_id uuid,p_product_name text,p_location_id uuid,p_notes text,p_lines jsonb,p_user_id uuid default auth.uid()) returns uuid
language plpgsql security definer set search_path=public as $$
declare v_id uuid; v jsonb; v_ing uuid; v_qty numeric;
begin
 if jsonb_array_length(coalesce(p_lines,'[]'::jsonb))=0 then raise exception 'Add raw materials used in production'; end if;
 insert into inventory_productions(branch_id,production_type,quantity,notes,created_by) values(p_branch_id,'FOOD',1,p_notes,p_user_id) returning id into v_id;
 for v in select * from jsonb_array_elements(p_lines) loop
  v_ing=(v->>'ingredient_id')::uuid; v_qty=(v->>'quantity')::numeric;
  perform nexa_inventory_post_movement(p_branch_id,v_ing,'PRODUCTION_OUT',v_qty,0,'PRODUCTION',v_id,p_notes,p_user_id);
 end loop;
 return v_id;
end$$;
grant execute on function public.nexa_inventory_receive_po(uuid,uuid) to authenticated;
grant execute on function public.nexa_inventory_post_production(uuid,text,uuid,text,jsonb,uuid) to authenticated;
