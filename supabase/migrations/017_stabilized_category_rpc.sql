-- NEXA stabilized build: secure category creation.
-- Uses the authenticated profile as the source of truth for branch + role.
create or replace function public.nexa_create_category(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_branch uuid;
  v_role text;
  v_id uuid;
begin
  if v_uid is null then raise exception 'Authentication required'; end if;
  select branch_id, role into v_branch, v_role
  from public.profiles
  where id = v_uid and active = true;
  if v_branch is null then raise exception 'Your staff account has no active branch'; end if;
  if v_role not in ('Admin','Manager') then raise exception 'Only Admin or Manager can create categories'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'Category name is required'; end if;
  insert into public.categories(branch_id,name,active)
  values(v_branch,trim(p_name),true)
  returning id into v_id;
  return v_id;
end;
$$;
revoke all on function public.nexa_create_category(text) from public;
grant execute on function public.nexa_create_category(text) to authenticated;
