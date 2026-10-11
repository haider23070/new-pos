alter table public.profiles add column if not exists employee_code text;
alter table public.profiles add column if not exists username text;
alter table public.profiles add column if not exists last_name text;
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists address text;
alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists hire_date date;
alter table public.profiles add column if not exists cnic text;
alter table public.profiles add column if not exists emergency_contact text;
alter table public.profiles add column if not exists blood_group text;
alter table public.profiles add column if not exists monthly_credit_limit numeric(12,2) default 0;
alter table public.profiles add column if not exists pin_code text;

create or replace function public.nexa_staff_list(p_all_branches boolean default false)
returns setof public.profiles language plpgsql stable security definer set search_path=public as $$
declare v_branch uuid; v_role text;
begin
 select p.branch_id,p.role into v_branch,v_role from public.profiles p where p.id=auth.uid() and p.active=true;
 if v_role not in ('Developer','Admin','Manager') then raise exception 'You do not have permission to view staff'; end if;
 if v_role='Developer' and coalesce(p_all_branches,false) then return query select * from public.profiles order by role,name; end if;
 return query select * from public.profiles where branch_id=v_branch order by role,name;
end $$;
revoke all on function public.nexa_staff_list(boolean) from public; grant execute on function public.nexa_staff_list(boolean) to authenticated;

create or replace function public.nexa_update_staff_profile(p_id uuid,p_patch jsonb)
returns public.profiles language plpgsql security definer set search_path=public as $$
declare me public.profiles; target public.profiles; outrow public.profiles; clean jsonb;
begin
 select * into me from public.profiles where id=auth.uid() and active=true;
 select * into target from public.profiles where id=p_id;
 if me.role not in ('Developer','Admin','Manager') then raise exception 'Permission denied'; end if;
 if me.role<>'Developer' and target.branch_id<>me.branch_id then raise exception 'Cross-branch update denied'; end if;
 if me.role<>'Developer' and coalesce(p_patch->>'role',target.role)='Developer' then raise exception 'Only Developer can assign Developer'; end if;
 clean=p_patch-'id'-'created_at'-'email'-'password'-'_mode';
 update public.profiles p set
  name=coalesce(clean->>'name',p.name), last_name=coalesce(clean->>'last_name',p.last_name), role=coalesce(clean->>'role',p.role),
  active=coalesce((clean->>'active')::boolean,p.active), employee_code=coalesce(clean->>'employee_code',p.employee_code), username=coalesce(clean->>'username',p.username),
  phone=coalesce(clean->>'phone',p.phone), address=coalesce(clean->>'address',p.address), city=coalesce(clean->>'city',p.city),
  hire_date=coalesce((nullif(clean->>'hire_date',''))::date,p.hire_date), cnic=coalesce(clean->>'cnic',p.cnic), emergency_contact=coalesce(clean->>'emergency_contact',p.emergency_contact),
  blood_group=coalesce(clean->>'blood_group',p.blood_group), monthly_credit_limit=coalesce((nullif(clean->>'monthly_credit_limit',''))::numeric,p.monthly_credit_limit),
  pin_code=coalesce(clean->>'pin_code',p.pin_code), receipt_printer_name=coalesce(clean->>'receipt_printer_name',p.receipt_printer_name),
  branch_id=case when me.role='Developer' then coalesce((clean->>'branch_id')::uuid,p.branch_id) else p.branch_id end
 where p.id=p_id returning * into outrow;
 return outrow;
end $$;
revoke all on function public.nexa_update_staff_profile(uuid,jsonb) from public; grant execute on function public.nexa_update_staff_profile(uuid,jsonb) to authenticated;
notify pgrst,'reload schema';
