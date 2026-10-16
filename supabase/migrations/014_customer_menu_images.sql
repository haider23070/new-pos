-- Customer-site menu imagery. Staff POS intentionally remains text-first.
alter table public.menu_items add column if not exists image_url text;
create or replace function public.nexa_public_menu(p_branch_id uuid)
returns table(item_id uuid,variant_id uuid,name text,variant_name text,price numeric,category_name text,image_url text)
language sql stable security definer set search_path=public as $$
 select i.id,v.id,i.name,v.name,v.price,c.name,i.image_url
 from menu_items i join menu_variants v on v.item_id=i.id left join categories c on c.id=i.category_id
 where i.branch_id=p_branch_id and coalesce(i.active,true)=true and coalesce(v.active,true)=true
 order by c.sort_order,c.name,i.name,v.price
$$;
grant execute on function public.nexa_public_menu(uuid) to anon,authenticated;
