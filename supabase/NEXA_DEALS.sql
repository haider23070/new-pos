-- NEXA Deals / Combo system
create table if not exists public.pos_deals (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.pos_branches(id) on delete cascade,
  name text not null,
  price numeric(12,2) not null check (price >= 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists public.pos_deal_items (
  id uuid primary key default gen_random_uuid(),
  deal_id uuid not null references public.pos_deals(id) on delete cascade,
  product_id uuid not null references public.pos_products(id) on delete restrict,
  variant_id uuid references public.pos_product_variants(id) on delete restrict,
  qty numeric(10,2) not null default 1 check (qty > 0),
  created_at timestamptz not null default now()
);
create index if not exists pos_deals_branch_idx on public.pos_deals(branch_id);
create index if not exists pos_deal_items_deal_idx on public.pos_deal_items(deal_id);
alter table public.pos_deals enable row level security;
alter table public.pos_deal_items enable row level security;
drop policy if exists "pos_deals_authenticated" on public.pos_deals;
create policy "pos_deals_authenticated" on public.pos_deals for all to authenticated using (true) with check (true);
drop policy if exists "pos_deal_items_authenticated" on public.pos_deal_items;
create policy "pos_deal_items_authenticated" on public.pos_deal_items for all to authenticated using (true) with check (true);
notify pgrst, 'reload schema';
