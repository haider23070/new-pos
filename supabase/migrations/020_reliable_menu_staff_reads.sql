-- NEXA v20: reliable authenticated read APIs for Menu Management and Staff.
-- Fixes records existing in DB but not appearing in dropdowns/lists because
-- multiple direct REST reads were individually filtered/failed by legacy RLS.

create or replace function public.nexa_menu_admin_snapshot()
returns jsonb
language plpgsql
stable
security definer
set search_path=public
as $$
declare
  v_branch uuid;
  v_role text;
  v_result jsonb;
begin
  if auth.uid() is null then raise exception 'You must be logged in'; end if;
  select p.branch_id,p.role into v_branch,v_role
  from public.profiles p where p.id=auth.uid() and p.active=true limit 1;
  if v_role is null then raise exception 'Active staff profile not found'; end if;
  if v_role not in ('Developer','Admin','Manager') then raise exception 'You do not have permission to manage the menu'; end if;
  if v_branch is null then raise exception 'Your account is not assigned to a branch'; end if;

  select jsonb_build_object(
    'categories',coalesce((select jsonb_agg(to_jsonb(c) order by coalesce(c.sort_order,0),c.name) from public.categories c where c.branch_id=v_branch),'[]'::jsonb),
    'departments',coalesce((select jsonb_agg(to_jsonb(d) order by d.name) from public.kitchen_departments d where d.branch_id=v_branch),'[]'::jsonb),
    'printers',coalesce((select jsonb_agg(to_jsonb(p) order by p.name) from public.printer_settings p where p.branch_id=v_branch),'[]'::jsonb),
    'items',coalesce((
      select jsonb_agg(
        to_jsonb(i) || jsonb_build_object('menu_variants',coalesce((select jsonb_agg(to_jsonb(v) order by v.price,v.name) from public.menu_variants v where v.item_id=i.id),'[]'::jsonb))
        order by i.name
      ) from public.menu_items i where i.branch_id=v_branch
    ),'[]'::jsonb)
  ) into v_result;
  return v_result;
end $$;
revoke all on function public.nexa_menu_admin_snapshot() from public;
grant execute on function public.nexa_menu_admin_snapshot() to authenticated;

create or replace function public.nexa_staff_list(p_all_branches boolean default false)
returns table(id uuid,branch_id uuid,name text,email text,role text,active boolean,created_at timestamptz)
language plpgsql
stable
security definer
set search_path=public
as $$
declare v_branch uuid; v_role text;
begin
  if auth.uid() is null then raise exception 'You must be logged in'; end if;
  select p.branch_id,p.role into v_branch,v_role from public.profiles p where p.id=auth.uid() and p.active=true limit 1;
  if v_role is null then raise exception 'Active staff profile not found'; end if;
  if v_role not in ('Developer','Admin','Manager') then raise exception 'You do not have permission to view staff'; end if;
  if v_role='Developer' and coalesce(p_all_branches,false) then
    return query select p.id,p.branch_id,p.name,p.email,p.role,p.active,p.created_at from public.profiles p order by p.name nulls last,p.email;
  end if;
  if v_branch is null then raise exception 'Your account is not assigned to a branch'; end if;
  return query select p.id,p.branch_id,p.name,p.email,p.role,p.active,p.created_at from public.profiles p where p.branch_id=v_branch order by p.name nulls last,p.email;
end $$;
revoke all on function public.nexa_staff_list(boolean) from public;
grant execute on function public.nexa_staff_list(boolean) to authenticated;

notify pgrst,'reload schema';
