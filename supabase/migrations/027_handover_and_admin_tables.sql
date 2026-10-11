-- v28: secure delivery transitions + Admin/Developer table creation
create or replace function public.nexa_delivery_transition(p_delivery_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_branch uuid; v_order uuid; v_rider uuid; v_role text:=public.nexa_my_role(); v_status text:=trim(p_status);
begin
 select branch_id,order_id,rider_id into v_branch,v_order,v_rider from public.deliveries where id=p_delivery_id;
 if v_branch is null then raise exception 'Delivery not found'; end if;
 if v_role not in ('Developer','Admin','Manager','Dispatcher') then raise exception 'Your role cannot update delivery handover'; end if;
 if v_role <> 'Developer' and v_branch <> public.nexa_my_branch() then raise exception 'You cannot update another branch delivery'; end if;
 if v_status not in ('Rider Out','Delivered') then raise exception 'Invalid delivery transition'; end if;
 if v_status='Rider Out' and v_rider is null then raise exception 'Assign a rider before handover'; end if;
 if v_status='Rider Out' and not exists(select 1 from public.riders where id=v_rider and branch_id=v_branch and on_duty=true) then raise exception 'Assigned rider is not on duty'; end if;
 update public.deliveries set status=v_status, handed_over_at=case when v_status='Rider Out' then coalesce(handed_over_at,now()) else handed_over_at end, delivered_at=case when v_status='Delivered' then coalesce(delivered_at,now()) else delivered_at end where id=p_delivery_id;
 update public.orders set delivery_status=v_status, status=case when v_status='Delivered' then 'Delivered' else status end where id=v_order and branch_id=v_branch;
 return jsonb_build_object('success',true,'delivery_id',p_delivery_id,'status',v_status);
end $$;
grant execute on function public.nexa_delivery_transition(uuid,text) to authenticated;

create or replace function public.nexa_admin_create_table(p_branch_id uuid,p_name text,p_seats integer default 4,p_floor_name text default 'Main Floor')
returns uuid language plpgsql security definer set search_path=public as $$
declare v_role text:=public.nexa_my_role(); v_id uuid;
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if v_role not in ('Developer','Admin') then raise exception 'Only Admin or Developer can add tables'; end if;
 if v_role <> 'Developer' and p_branch_id <> public.nexa_my_branch() then raise exception 'Admin can add tables only to their own branch'; end if;
 if nullif(trim(p_name),'') is null then raise exception 'Table name is required'; end if;
 if coalesce(p_seats,0)<1 or p_seats>50 then raise exception 'Seats must be between 1 and 50'; end if;
 if exists(select 1 from public.restaurant_tables where branch_id=p_branch_id and lower(name)=lower(trim(p_name))) then raise exception 'A table with this name already exists'; end if;
 insert into public.restaurant_tables(branch_id,name,seats,status,active,floor_name) values(p_branch_id,trim(p_name),p_seats,'available',true,coalesce(nullif(trim(p_floor_name),''),'Main Floor')) returning id into v_id;
 return v_id;
end $$;
grant execute on function public.nexa_admin_create_table(uuid,text,integer,text) to authenticated;
notify pgrst,'reload schema';
