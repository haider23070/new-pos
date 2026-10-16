-- NEXA v23: public branch discovery + Developer branch deletion
create or replace function public.nexa_public_branches()
returns table(id uuid,name text,address text,phone text,latitude numeric,longitude numeric,delivery_radius_km numeric)
language sql stable security definer set search_path=public
as $$
  select b.id,b.name,b.address,b.phone,b.latitude,b.longitude,coalesce(b.delivery_radius_km,8)
  from public.branches b
  where coalesce(b.active,true)=true
  order by b.name;
$$;
revoke all on function public.nexa_public_branches() from public;
grant execute on function public.nexa_public_branches() to anon,authenticated;

create or replace function public.nexa_developer_delete_branch(p_branch_id uuid)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_role text; v_name text;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  select p.role into v_role from public.profiles p where p.id=auth.uid() and coalesce(p.active,true)=true limit 1;
  if v_role is distinct from 'Developer' then raise exception 'Only Developer can delete branches'; end if;
  select name into v_name from public.branches where id=p_branch_id;
  if v_name is null then raise exception 'Branch not found'; end if;
  if exists(select 1 from public.profiles where branch_id=p_branch_id and id<>auth.uid()) then
    raise exception 'Move staff to another branch before deleting this branch';
  end if;
  begin
    delete from public.branches where id=p_branch_id;
  exception when foreign_key_violation then
    raise exception 'This branch has operational history and cannot be permanently deleted. Set it inactive instead.';
  end;
  return jsonb_build_object('success',true,'deleted_branch',v_name);
end $$;
revoke all on function public.nexa_developer_delete_branch(uuid) from public;
grant execute on function public.nexa_developer_delete_branch(uuid) to authenticated;
notify pgrst,'reload schema';
