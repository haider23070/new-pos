-- NEXA consolidated stabilization: canonical auth context, Developer control,
-- secure menu writes, expenses, branches and stock transfers.

-- Canonical session identity is auth.users -> profiles. Fall back to legacy users only when needed.
create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$
 select coalesce((select p.branch_id from public.profiles p where p.id=auth.uid() and p.active=true limit 1),(select u.branch_id from public.users u where u.auth_id=auth.uid() and u.status='Active' limit 1))
$$;
create or replace function public.nexa_my_role() returns text language sql stable security definer set search_path=public as $$
 select coalesce((select p.role from public.profiles p where p.id=auth.uid() and p.active=true limit 1),(select u.role from public.users u where u.auth_id=auth.uid() and u.status='Active' limit 1))
$$;
create or replace function public.current_branch_id() returns uuid language sql stable security definer set search_path=public as $$ select public.nexa_my_branch() $$;
create or replace function public.current_role() returns text language sql stable security definer set search_path=public as $$ select public.nexa_my_role() $$;
create or replace function public.is_management() returns boolean language sql stable security definer set search_path=public as $$ select coalesce(public.nexa_my_role() in ('Developer','Admin','Manager'),false) $$;
create or replace function public.can_access_branch(target uuid) returns boolean language sql stable security definer set search_path=public as $$
 select coalesce(public.nexa_my_role()='Developer' or target=public.nexa_my_branch(),false)
$$;
grant execute on function public.nexa_my_branch() to authenticated;
grant execute on function public.nexa_my_role() to authenticated;

insert into public.roles(name) values('Developer') on conflict(name) do nothing;

-- Developer can see/manage branches. Existing branch read policy remains for normal roles.
drop policy if exists nexa_developer_branches_all on public.branches;
create policy nexa_developer_branches_all on public.branches for all to authenticated
 using(public.nexa_my_role()='Developer') with check(public.nexa_my_role()='Developer');

create or replace function public.nexa_developer_save_branch(p_id uuid,p_name text,p_address text default null,p_phone text default null,p_active boolean default true)
returns public.branches language plpgsql security definer set search_path=public as $$
declare v public.branches;
begin
 if public.nexa_my_role()<>'Developer' then raise exception 'Only Developer can create or edit branches'; end if;
 if nullif(trim(p_name),'') is null then raise exception 'Branch name is required'; end if;
 if p_id is null then
   insert into branches(name,address,phone,active) values(trim(p_name),nullif(trim(p_address),''),nullif(trim(p_phone),''),coalesce(p_active,true)) returning * into v;
 else
   update branches set name=trim(p_name),address=nullif(trim(p_address),''),phone=nullif(trim(p_phone),''),active=coalesce(p_active,true) where id=p_id returning * into v;
   if v.id is null then raise exception 'Branch not found'; end if;
 end if;
 return v;
end $$;
grant execute on function public.nexa_developer_save_branch(uuid,text,text,text,boolean) to authenticated;

-- Clean branch policies for menu reads/writes. Developer may manage any branch; Admin/Manager own branch.
alter table public.categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.menu_variants enable row level security;
alter table public.kitchen_departments enable row level security;
alter table public.printer_settings enable row level security;

drop policy if exists nexa_menu_categories_read_v19 on public.categories;
create policy nexa_menu_categories_read_v19 on public.categories for select to authenticated using(public.nexa_my_role()='Developer' or branch_id=public.nexa_my_branch());
drop policy if exists nexa_menu_items_read_v19 on public.menu_items;
create policy nexa_menu_items_read_v19 on public.menu_items for select to authenticated using(public.nexa_my_role()='Developer' or branch_id=public.nexa_my_branch());
drop policy if exists nexa_menu_variants_read_v19 on public.menu_variants;
create policy nexa_menu_variants_read_v19 on public.menu_variants for select to authenticated using(exists(select 1 from menu_items m where m.id=item_id and (public.nexa_my_role()='Developer' or m.branch_id=public.nexa_my_branch())));
drop policy if exists nexa_departments_read_v19 on public.kitchen_departments;
create policy nexa_departments_read_v19 on public.kitchen_departments for select to authenticated using(public.nexa_my_role()='Developer' or branch_id=public.nexa_my_branch());
drop policy if exists nexa_printers_read_v19 on public.printer_settings;
create policy nexa_printers_read_v19 on public.printer_settings for select to authenticated using(public.nexa_my_role()='Developer' or branch_id=public.nexa_my_branch());

create or replace function public.nexa_create_category(p_name text) returns public.categories language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=public.nexa_my_branch();v_role text:=public.nexa_my_role();v public.categories;
begin if v_role not in('Developer','Admin','Manager') then raise exception 'Not allowed';end if;if v_branch is null then raise exception 'No branch assigned';end if;if nullif(trim(p_name),'') is null then raise exception 'Category name is required';end if;insert into categories(branch_id,name,active) values(v_branch,trim(p_name),true) returning * into v;return v;end $$;
grant execute on function public.nexa_create_category(text) to authenticated;

create or replace function public.nexa_create_kitchen_department(p_name text) returns public.kitchen_departments language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=public.nexa_my_branch();v_role text:=public.nexa_my_role();v public.kitchen_departments;
begin if v_role not in('Developer','Admin','Manager') then raise exception 'Not allowed';end if;if v_branch is null then raise exception 'No branch assigned';end if;if nullif(trim(p_name),'') is null then raise exception 'Department name is required';end if;insert into kitchen_departments(branch_id,name,active) values(v_branch,trim(p_name),true) returning * into v;return v;end $$;
grant execute on function public.nexa_create_kitchen_department(text) to authenticated;

create or replace function public.nexa_create_menu_item(p_name text,p_category_id uuid,p_department_id uuid,p_variant_name text,p_price numeric,p_image_url text default null)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=public.nexa_my_branch();v_role text:=public.nexa_my_role();v_id uuid;
begin
 if v_role not in('Developer','Admin','Manager') then raise exception 'Not allowed';end if;
 if v_branch is null then raise exception 'No branch assigned';end if;
 if nullif(trim(p_name),'') is null then raise exception 'Item name is required';end if;
 if p_price is null or p_price<0 then raise exception 'Valid price is required';end if;
 if p_category_id is not null and not exists(select 1 from categories where id=p_category_id and branch_id=v_branch) then raise exception 'Category does not belong to your branch';end if;
 if p_department_id is not null and not exists(select 1 from kitchen_departments where id=p_department_id and branch_id=v_branch) then raise exception 'Department does not belong to your branch';end if;
 insert into menu_items(branch_id,category_id,department_id,name,image_url,active) values(v_branch,p_category_id,p_department_id,trim(p_name),nullif(trim(p_image_url),''),true) returning id into v_id;
 insert into menu_variants(item_id,name,price,is_default,active) values(v_id,coalesce(nullif(trim(p_variant_name),''),'Regular'),p_price,true,true);
 return v_id;
end $$;
grant execute on function public.nexa_create_menu_item(text,uuid,uuid,text,numeric,text) to authenticated;

create or replace function public.nexa_toggle_menu_item(p_item_id uuid,p_active boolean) returns boolean language plpgsql security definer set search_path=public as $$
begin if public.nexa_my_role() not in('Developer','Admin','Manager') then raise exception 'Not allowed';end if;update menu_items set active=p_active where id=p_item_id and branch_id=public.nexa_my_branch();if not found then raise exception 'Menu item not found in your branch';end if;return p_active;end $$;
grant execute on function public.nexa_toggle_menu_item(uuid,boolean) to authenticated;

create or replace function public.nexa_save_kitchen_printer(p_name text,p_printer_name text,p_department_id uuid) returns uuid language plpgsql security definer set search_path=public as $$
declare v_branch uuid:=public.nexa_my_branch();v_id uuid;
begin if public.nexa_my_role() not in('Developer','Admin','Manager') then raise exception 'Not allowed';end if;if not exists(select 1 from kitchen_departments where id=p_department_id and branch_id=v_branch) then raise exception 'Department not found';end if;delete from printer_settings where branch_id=v_branch and department_id=p_department_id;insert into printer_settings(branch_id,name,printer_name,department_id,paper_width_mm,auto_print,active) values(v_branch,trim(p_name),trim(p_printer_name),p_department_id,80,true,true) returning id into v_id;update kitchen_departments set printer_name=trim(p_printer_name) where id=p_department_id;return v_id;end $$;
grant execute on function public.nexa_save_kitchen_printer(text,text,uuid) to authenticated;

-- Expense entry. Normalize the legacy table without destroying existing data.
alter table public.expenses add column if not exists category text;
alter table public.expenses add column if not exists description text;
alter table public.expenses add column if not exists created_by uuid;
alter table public.expenses add column if not exists created_at timestamptz default now();
alter table public.expenses enable row level security;
drop policy if exists nexa_expenses_read_v19 on public.expenses;
create policy nexa_expenses_read_v19 on public.expenses for select to authenticated using(public.nexa_my_role()='Developer' or branch_id=public.nexa_my_branch());
create or replace function public.nexa_create_expense(p_category text,p_description text,p_amount numeric) returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid;v_branch uuid:=public.nexa_my_branch();
begin if public.nexa_my_role() not in('Developer','Admin','Manager') then raise exception 'Not allowed to add expenses';end if;if v_branch is null then raise exception 'No branch assigned';end if;if p_amount is null or p_amount<=0 then raise exception 'Expense amount must be greater than zero';end if;insert into expenses(branch_id,category,description,amount,created_by) values(v_branch,coalesce(nullif(trim(p_category),''),'General'),nullif(trim(p_description),''),p_amount,auth.uid()) returning id into v_id;return v_id;end $$;
grant execute on function public.nexa_create_expense(text,text,numeric) to authenticated;

-- Secure branch transfer with row lock and matching destination ingredient.
create or replace function public.nexa_create_stock_transfer(p_ingredient_id uuid,p_qty numeric,p_to_branch_id uuid,p_notes text default null) returns uuid language plpgsql security definer set search_path=public as $$
declare v_from uuid:=public.nexa_my_branch();v_role text:=public.nexa_my_role();v_src inventory_ingredients%rowtype;v_dest_id uuid;v_transfer uuid;v_src_after numeric;v_dest_after numeric;
begin
 if v_role not in('Developer','Admin','Manager') then raise exception 'Not allowed to transfer stock';end if;
 if p_qty is null or p_qty<=0 then raise exception 'Quantity must be greater than zero';end if;
 if p_to_branch_id is null or p_to_branch_id=v_from then raise exception 'Choose another destination branch';end if;
 if not exists(select 1 from branches where id=p_to_branch_id and active=true) then raise exception 'Destination branch is not active';end if;
 select * into v_src from inventory_ingredients where id=p_ingredient_id and branch_id=v_from for update;
 if not found then raise exception 'Ingredient not found in source branch';end if;
 if v_src.current_stock<p_qty then raise exception 'Insufficient stock. Available: % %',v_src.current_stock,v_src.unit;end if;
 select id into v_dest_id from inventory_ingredients where branch_id=p_to_branch_id and lower(name)=lower(v_src.name) limit 1;
 if v_dest_id is null then insert into inventory_ingredients(branch_id,category_id,name,unit,current_stock,min_stock,avg_cost,active) values(p_to_branch_id,null,v_src.name,v_src.unit,0,v_src.min_stock,v_src.avg_cost,true) returning id into v_dest_id;end if;
 update inventory_ingredients set current_stock=current_stock-p_qty,updated_at=now() where id=v_src.id returning current_stock into v_src_after;
 update inventory_ingredients set current_stock=current_stock+p_qty,avg_cost=v_src.avg_cost,updated_at=now() where id=v_dest_id returning current_stock into v_dest_after;
 insert into inventory_transfers(from_branch_id,to_branch_id,ingredient_id,quantity,status,notes,created_by) values(v_from,p_to_branch_id,v_src.id,p_qty,'SENT',p_notes,auth.uid()) returning id into v_transfer;
 insert into inventory_movements(branch_id,movement_type,ingredient_id,quantity,balance_after,unit_cost,reference_type,reference_id,notes,created_by) values(v_from,'TRANSFER_OUT',v_src.id,-p_qty,v_src_after,v_src.avg_cost,'TRANSFER',v_transfer,p_notes,auth.uid());
 insert into inventory_movements(branch_id,movement_type,ingredient_id,quantity,balance_after,unit_cost,reference_type,reference_id,notes,created_by) values(p_to_branch_id,'TRANSFER_IN',v_dest_id,p_qty,v_dest_after,v_src.avg_cost,'TRANSFER',v_transfer,p_notes,auth.uid());
 return v_transfer;
end $$;
grant execute on function public.nexa_create_stock_transfer(uuid,numeric,uuid,text) to authenticated;

-- Developer can inspect staff profiles across branches. Normal staff remain branch-scoped by existing policies.
drop policy if exists nexa_developer_profiles_read on public.profiles;
create policy nexa_developer_profiles_read on public.profiles for select to authenticated using(public.nexa_my_role()='Developer');

notify pgrst,'reload schema';

-- Branch names are operational reference data (transfers, staff assignment); authenticated users may read them.
drop policy if exists nexa_branches_reference_read on public.branches;
create policy nexa_branches_reference_read on public.branches for select to authenticated using(true);

-- Staff management on canonical profiles.
alter table public.profiles enable row level security;
drop policy if exists nexa_management_profiles_read on public.profiles;
create policy nexa_management_profiles_read on public.profiles for select to authenticated
 using(public.nexa_my_role()='Developer' or (public.nexa_my_role() in('Admin','Manager') and branch_id=public.nexa_my_branch()));
drop policy if exists nexa_management_profiles_update on public.profiles;
create policy nexa_management_profiles_update on public.profiles for update to authenticated
 using(public.nexa_my_role()='Developer' or (public.nexa_my_role() in('Admin','Manager') and branch_id=public.nexa_my_branch()))
 with check((public.nexa_my_role()='Developer') or (branch_id=public.nexa_my_branch() and role<>'Developer'));

-- Developer break-glass/full-control policies for the principal branch-owned operational tables.
do $$
declare t text;
begin
 foreach t in array array['orders','payments','expenses','shifts','deliveries','categories','menu_items','kitchen_departments','printer_settings','inventory_categories','inventory_ingredients','inventory_recipes','inventory_purchases','inventory_movements','inventory_wastage','inventory_closings','inventory_transfers','suppliers','audit_log','notifications'] loop
   if to_regclass('public.'||t) is not null then
     execute format('alter table public.%I enable row level security',t);
     execute format('drop policy if exists %I on public.%I','nexa_developer_all_'||t,t);
     execute format('create policy %I on public.%I for all to authenticated using(public.nexa_my_role()=''Developer'') with check(public.nexa_my_role()=''Developer'')','nexa_developer_all_'||t,t);
   end if;
 end loop;
end $$;
notify pgrst,'reload schema';
