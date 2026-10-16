-- NEXA POS automatic token numbering.
-- Safe to run more than once.
-- Tokens restart at 1 for each branch + shift and remain unchanged when an order is edited.

-- Backfill only orders that currently have no token.
with missing as (
  select id,
         row_number() over (partition by branch_id, shift_id order by created_at, id) as rn,
         coalesce((select max(o2.token_no) from public.pos_orders o2
                   where o2.branch_id = o.branch_id
                     and o2.shift_id is not distinct from o.shift_id
                     and o2.token_no is not null), 0) as base
  from public.pos_orders o
  where token_no is null
)
update public.pos_orders o
set token_no = missing.base + missing.rn
from missing
where o.id = missing.id;

create unique index if not exists pos_orders_branch_shift_token_uidx
  on public.pos_orders(branch_id, shift_id, token_no)
  where token_no is not null;

create or replace function public.pos_assign_order_token()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.token_no is null then
    -- Serialize token allocation inside a branch/shift to prevent duplicate tokens.
    perform pg_advisory_xact_lock(hashtext(new.branch_id::text || ':' || coalesce(new.shift_id::text, 'no-shift')));
    select coalesce(max(token_no), 0) + 1
      into new.token_no
      from public.pos_orders
     where branch_id = new.branch_id
       and shift_id is not distinct from new.shift_id;
  end if;
  return new;
end;
$$;

drop trigger if exists pos_orders_assign_token on public.pos_orders;
create trigger pos_orders_assign_token
before insert on public.pos_orders
for each row execute function public.pos_assign_order_token();
