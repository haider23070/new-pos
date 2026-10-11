-- NEXA Phase 3: POS persistence, numbering and branch RLS
alter table public.orders add column if not exists notes text;
alter table public.orders add column if not exists updated_at timestamptz default now();
create sequence if not exists public.nexa_order_token_seq start 1;
create or replace function public.nexa_set_order_numbers() returns trigger language plpgsql as $$
begin
 if new.token is null then new.token := nextval('public.nexa_order_token_seq'); end if;
 if new.invoice_no is null then new.invoice_no := 'NX-'||to_char(now(),'YYMMDD')||'-'||lpad(new.token::text,5,'0'); end if;
 return new;
end $$;
drop trigger if exists trg_nexa_order_numbers on public.orders;
create trigger trg_nexa_order_numbers before insert on public.orders for each row execute function public.nexa_set_order_numbers();

alter table public.categories enable row level security;
alter table public.menu_items enable row level security;
alter table public.menu_variants enable row level security;
alter table public.customers enable row level security;
alter table public.restaurant_tables enable row level security;
alter table public.order_items enable row level security;
alter table public.payments enable row level security;

create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$ select branch_id from public.users where auth_id=auth.uid() limit 1 $$;

do $$ begin
 create policy "p3 categories read" on public.categories for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 menu read" on public.menu_items for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 variants read" on public.menu_variants for select to authenticated using(exists(select 1 from public.menu_items m where m.id=item_id and m.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 customers all" on public.customers for all to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 tables read" on public.restaurant_tables for select to authenticated using(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 orders update" on public.orders for update to authenticated using(branch_id=public.nexa_my_branch()) with check(branch_id=public.nexa_my_branch()); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 orderitems read" on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 orderitems insert" on public.order_items for insert to authenticated with check(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 payments read" on public.payments for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;
do $$ begin
 create policy "p3 payments insert" on public.payments for insert to authenticated with check(exists(select 1 from public.orders o where o.id=order_id and o.branch_id=public.nexa_my_branch())); exception when duplicate_object then null; end $$;

alter table public.orders replica identity full;
do $$ begin alter publication supabase_realtime add table public.orders; exception when duplicate_object then null; end $$;
