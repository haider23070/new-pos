-- NEXA v34: cashier expense entry permission.
-- UI-only access changes (Customers, Notifications, Settings/Tables) are enforced in the app.
create or replace function public.nexa_create_expense(p_category text,p_description text,p_amount numeric)
returns uuid language plpgsql security definer set search_path=public as $$
declare v_id uuid; v_branch uuid:=public.nexa_my_branch(); v_role text:=public.nexa_my_role();
begin
 if v_role not in('Developer','Admin','Manager','Cashier') then raise exception 'Not allowed to add expenses'; end if;
 if v_branch is null then raise exception 'No branch assigned'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Expense amount must be greater than zero'; end if;
 insert into expenses(branch_id,category,description,amount,created_by)
 values(v_branch,coalesce(nullif(trim(p_category),''),'General'),nullif(trim(p_description),''),p_amount,auth.uid())
 returning id into v_id;
 return v_id;
end $$;
grant execute on function public.nexa_create_expense(text,text,numeric) to authenticated;
notify pgrst,'reload schema';
