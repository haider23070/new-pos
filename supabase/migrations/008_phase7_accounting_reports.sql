-- NEXA Phase 7: Accounting + Reports (schema-compatible with the core NEXA tables)
-- Depends on migrations 001-006. Uses stock_movements + ingredients, not legacy inventory_movements.
create extension if not exists pgcrypto;

create or replace function public.nexa_my_branch() returns uuid language sql stable security definer set search_path=public as $$
  select branch_id from public.users where auth_id=auth.uid() limit 1
$$;
grant execute on function public.nexa_my_branch() to authenticated;

create index if not exists idx_orders_branch_created on public.orders(branch_id,created_at);
create index if not exists idx_orders_branch_completed on public.orders(branch_id,completed_at);
create index if not exists idx_payments_created on public.payments(created_at);
create index if not exists idx_expenses_branch_created on public.expenses(branch_id,created_at);
create index if not exists idx_shifts_branch_opened on public.shifts(branch_id,opened_at);
create index if not exists idx_stock_mov_branch_created on public.stock_movements(branch_id,created_at);

create or replace function public.nexa_finance_dashboard(p_start date,p_end date)
returns table(gross_sales numeric,discounts numeric,tax numeric,net_sales numeric,orders bigint,collected numeric,due_amount numeric,expenses numeric,purchases numeric,cogs numeric,wastage numeric,gross_profit numeric,gross_margin numeric,net_profit numeric)
language sql stable security definer set search_path=public as $$
with o as (
 select coalesce(sum(total),0) gross_sales,coalesce(sum(discount),0) discounts,coalesce(sum(tax),0) tax,coalesce(sum(grand_total),0) net_sales,count(*) orders
 from orders where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), p as (
 select coalesce(sum(case when p.reversed_at is null and lower(coalesce(p.status,'')) not in ('reversed','cancelled') then p.amount else 0 end),0) collected
 from payments p join orders o2 on o2.id=p.order_id where o2.branch_id=nexa_my_branch() and p.created_at>=p_start::timestamptz and p.created_at<(p_end+1)::timestamptz
), e as (
 select coalesce(sum(amount),0) expenses from expenses where branch_id=nexa_my_branch() and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), pu as (
 select coalesce(sum(total),0) purchases from purchases where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','rejected') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz
), c as (
 select
   coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('sale','consumption','recipe_consumption','order_consumption','stock_out')),0) cogs,
   coalesce(sum(abs(sm.quantity)*coalesce(i.cost,0)) filter(where lower(sm.type) in ('wastage','waste')),0) wastage
 from stock_movements sm left join ingredients i on i.id=sm.ingredient_id
 where sm.branch_id=nexa_my_branch() and sm.created_at>=p_start::timestamptz and sm.created_at<(p_end+1)::timestamptz
)
select o.gross_sales,o.discounts,o.tax,o.net_sales,o.orders,p.collected,greatest(o.net_sales-p.collected,0),e.expenses,pu.purchases,c.cogs,c.wastage,
(o.net_sales-o.tax-c.cogs),case when o.net_sales-o.tax=0 then 0 else ((o.net_sales-o.tax-c.cogs)/(o.net_sales-o.tax))*100 end,
(o.net_sales-o.tax-c.cogs-e.expenses-c.wastage) from o,p,e,pu,c;
$$;

create or replace function public.nexa_daily_sales(p_start date,p_end date)
returns table(sale_date date,orders bigint,gross_sales numeric,discounts numeric,tax numeric,net_sales numeric,avg_bill numeric)
language sql stable security definer set search_path=public as $$
 select (created_at at time zone 'Asia/Karachi')::date,count(*),coalesce(sum(total),0),coalesce(sum(discount),0),coalesce(sum(tax),0),coalesce(sum(grand_total),0),coalesce(avg(grand_total),0)
 from orders where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz group by 1 order by 1;
$$;

create or replace function public.nexa_payment_summary(p_start date,p_end date)
returns table(method text,transactions bigint,collected numeric,reversed numeric,net_collection numeric)
language sql stable security definer set search_path=public as $$
 select p.method,count(*),coalesce(sum(case when p.reversed_at is null then p.amount else 0 end),0),coalesce(sum(case when p.reversed_at is not null then p.amount else 0 end),0),coalesce(sum(case when p.reversed_at is null then p.amount else -p.amount end),0)
 from payments p join orders o on o.id=p.order_id where o.branch_id=nexa_my_branch() and p.created_at>=p_start::timestamptz and p.created_at<(p_end+1)::timestamptz group by p.method order by 5 desc;
$$;

create or replace function public.nexa_expense_summary(p_start date,p_end date)
returns table(category text,entries bigint,amount numeric)
language sql stable security definer set search_path=public as $$
 select coalesce(nullif(e.category,''),'Uncategorized'),count(*),coalesce(sum(e.amount),0) from expenses e
 where e.branch_id=nexa_my_branch() and e.created_at>=p_start::timestamptz and e.created_at<(p_end+1)::timestamptz group by 1 order by 3 desc;
$$;

create or replace function public.nexa_profit_loss(p_start date,p_end date)
returns table(metric text,amount numeric)
language sql stable security definer set search_path=public as $$
 with d as (select * from nexa_finance_dashboard(p_start,p_end))
 select 'Net Sales',net_sales from d union all select 'Less: Tax / VAT',-tax from d union all select 'Less: Cost of Goods Sold',-cogs from d union all select 'Gross Profit',gross_profit from d union all select 'Less: Operating Expenses',-expenses from d union all select 'Less: Wastage',-wastage from d union all select 'Estimated Net Profit',net_profit from d;
$$;

create or replace function public.nexa_tax_summary(p_start date,p_end date)
returns table(sale_date date,taxable_sales numeric,tax_collected numeric,orders bigint)
language sql stable security definer set search_path=public as $$
 select (created_at at time zone 'Asia/Karachi')::date,coalesce(sum(grand_total-tax),0),coalesce(sum(tax),0),count(*) from orders
 where branch_id=nexa_my_branch() and lower(coalesce(status,'')) not in ('cancelled','draft') and created_at>=p_start::timestamptz and created_at<(p_end+1)::timestamptz group by 1 order by 1;
$$;

create or replace function public.nexa_shift_summary(p_start date,p_end date)
returns table(opened_at timestamptz,closed_at timestamptz,status text,opening_cash numeric,cash_sales numeric,expenses numeric,expected_cash numeric,closing_cash numeric,difference numeric)
language sql stable security definer set search_path=public as $$
 select s.opened_at,s.closed_at,s.status,s.opening_cash,
 coalesce((select sum(p.amount) from payments p join orders o on o.id=p.order_id where o.shift_id=s.id and lower(p.method)='cash' and p.reversed_at is null),0),
 coalesce((select sum(e.amount) from expenses e where e.shift_id=s.id),0),coalesce(s.expected_cash,0),coalesce(s.actual_cash,0),coalesce(s.actual_cash,0)-coalesce(s.expected_cash,0)
 from shifts s where s.branch_id=nexa_my_branch() and s.opened_at>=p_start::timestamptz and s.opened_at<(p_end+1)::timestamptz order by s.opened_at desc;
$$;

grant execute on function public.nexa_finance_dashboard(date,date),public.nexa_daily_sales(date,date),public.nexa_payment_summary(date,date),public.nexa_expense_summary(date,date),public.nexa_profit_loss(date,date),public.nexa_tax_summary(date,date),public.nexa_shift_summary(date,date) to authenticated;

alter table public.payments replica identity full;
alter table public.expenses replica identity full;
