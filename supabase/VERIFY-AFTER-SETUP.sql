-- Run after the main setup SQL and the one-time Admin bootstrap SQL.
select table_name
from information_schema.tables
where table_schema='public' and table_type='BASE TABLE'
order by table_name;

select name, code_prefix from public.categories order by name;

select p.id, p.full_name, p.username, p.role, p.is_active, u.email
from public.profiles p join auth.users u on u.id=p.id
where p.role='admin';

select id, name, public, file_size_limit
from storage.buckets where id='ananta-product-photos';

-- Security flags: all application tables must have RLS enabled.
select c.relname as table_name, c.relrowsecurity as rls_enabled
from pg_class c join pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r'
  and c.relname in ('profiles','categories','products','product_variants','variant_costs','customers','customer_aliases','paper_bills','paper_bill_items','paper_bill_item_costs','stock_movements','expense_categories','cashbook_expenses','cashbook_refunds','app_notifications','activity_log')
order by c.relname;