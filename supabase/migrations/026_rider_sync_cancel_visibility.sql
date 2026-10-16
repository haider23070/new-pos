-- NEXA v27: keep Delivery Boy profiles represented in riders and cancelled orders out of live delivery queues.
-- Safe/idempotent compatibility migration for databases where staff profiles existed before the riders row was created.

insert into public.riders(profile_id,branch_id,on_duty,cash_balance)
select p.id,p.branch_id,false,0
from public.profiles p
where lower(trim(coalesce(p.role,''))) in ('delivery boy','delivery','rider')
  and coalesce(p.active,true)=true
  and p.branch_id is not null
  and not exists(select 1 from public.riders r where r.profile_id=p.id);

-- Cancelled orders are historical only. Keep a delivery queue row for audit/history if it already exists,
-- but mark it cancelled so live operational screens can exclude it consistently.
update public.deliveries d
set status='Cancelled'
from public.orders o
where o.id=d.order_id
  and lower(coalesce(o.status,''))='cancelled'
  and lower(coalesce(d.status,''))<>'cancelled';

notify pgrst,'reload schema';
