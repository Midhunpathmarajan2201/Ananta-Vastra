-- ============================================================================
-- ANANTA VASTRA - SUPABASE DATABASE SETUP (initial V1)
-- Project: hctqowxkhdouclbqvejh
-- Run the entire script once in Supabase SQL Editor as postgres.
-- This script creates application tables, RLS, RPCs, indexes, seed categories,
-- a private product-photo bucket, and Realtime publication membership.
--
-- IMPORTANT AUTH SETUP (after this SQL succeeds):
-- 1) Disable public sign-ups in Supabase Auth settings.
-- 2) In Authentication > Users, create/confirm the single owner Auth user
--    for yogisharajan@gmail.com using the password chosen by the owner.
-- 3) Run the separate one-time Admin profile bootstrap SQL in
--    supabase/ADMIN-BOOTSTRAP-AFTER-AUTH-USER.sql.
-- 4) Deploy supabase/functions/manage-sales-employee. Sales accounts are
--    created/reset/deactivated/reactivated only by this Admin-only function.
--
-- No password or service-role secret is stored in this file.
-- Suppliers are intentionally excluded from this V1 release.
-- ============================================================================

begin;

-- gen_random_uuid() is built into supported Supabase PostgreSQL versions.

-- ---------------------------------------------------------------------------
-- Core identities and catalogue
-- ---------------------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null,
  username text not null,
  role text not null default 'sales' check (role in ('admin','sales')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deactivated_at timestamptz,
  session_iat_valid_after bigint not null default 0 check (session_iat_valid_after >= 0)
);
create unique index if not exists profiles_username_ci_uq on public.profiles (lower(username));
create unique index if not exists one_ananta_vastra_admin on public.profiles (role) where role='admin';

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code_prefix text not null check (code_prefix ~ '^[A-Z0-9-]{1,12}$'),
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists categories_name_ci_uq on public.categories(lower(name));
create unique index if not exists categories_prefix_ci_uq on public.categories(lower(code_prefix));

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null,
  product_code text not null,
  notes text,
  photo_path text,
  is_archived boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);
create unique index if not exists products_code_ci_uq on public.products(lower(product_code));
create index if not exists products_category_idx on public.products(category_id) where is_archived=false;

-- Internal per-category counter used to generate stable codes such as 2PC-00001.
create table if not exists public.product_code_sequences (
  category_id uuid primary key references public.categories(id) on delete restrict,
  last_number bigint not null default 0 check (last_number >= 0)
);
alter table public.product_code_sequences enable row level security;

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  color text,
  size text,
  stock_on_hand integer not null default 0 check (stock_on_hand >= 0),
  damaged_qty integer not null default 0 check (damaged_qty >= 0),
  pending_inspection_qty integer not null default 0 check (pending_inspection_qty >= 0),
  selling_price numeric(12,2) not null check (selling_price >= 0),
  min_stock integer not null default 0 check (min_stock >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  archived_at timestamptz
);
create unique index if not exists variants_product_color_size_ci_uq
  on public.product_variants(product_id, lower(coalesce(color,'')), lower(coalesce(size,'')))
  where is_active=true;
create index if not exists variants_product_idx on public.product_variants(product_id) where is_active=true;

-- Costs are deliberately stored separately so Sales cannot read purchase prices.
create table if not exists public.variant_costs (
  variant_id uuid primary key references public.product_variants(id) on delete restrict,
  purchase_price numeric(12,2) check (purchase_price is null or purchase_price >= 0),
  cost_history jsonb not null default '[]'::jsonb,
  updated_by uuid references public.profiles(id),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Customers, paper bills, bill lines and stock ledger
-- ---------------------------------------------------------------------------
create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  phone text,
  phone_normalized text unique,
  created_at timestamptz not null default now(),
  check (phone_normalized is null or phone_normalized ~ '^[0-9]{7,15}$')
);
create table if not exists public.customer_aliases (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  customer_name text not null,
  normalized_name text not null,
  first_seen_at timestamptz not null default now(),
  unique(customer_id, normalized_name)
);

create table if not exists public.paper_bills (
  id uuid primary key default gen_random_uuid(),
  physical_bill_number text not null,
  bill_date date not null,
  customer_id uuid references public.customers(id) on delete restrict,
  customer_name_snapshot text not null,
  customer_phone_snapshot text,
  sold_by uuid not null references public.profiles(id) on delete restrict,
  entered_by uuid not null references public.profiles(id) on delete restrict,
  entered_at timestamptz not null default now(),
  subtotal numeric(12,2) not null default 0 check (subtotal >= 0),
  admin_discount numeric(12,2) not null default 0 check (admin_discount >= 0),
  final_amount numeric(12,2) not null check (final_amount >= 0),
  cash_amount numeric(12,2) not null default 0 check (cash_amount >= 0),
  upi_amount numeric(12,2) not null default 0 check (upi_amount >= 0),
  amount_overridden boolean not null default false,
  status text not null default 'posted' check (status in ('posted','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id),
  cancelled_at timestamptz,
  cancelled_by uuid references public.profiles(id),
  correction_history jsonb not null default '[]'::jsonb,
  check (abs((cash_amount + upi_amount) - final_amount) <= 0.01)
);
create unique index if not exists paper_bills_number_ci_uq on public.paper_bills(lower(trim(physical_bill_number)));
create index if not exists paper_bills_date_idx on public.paper_bills(bill_date desc);
create index if not exists paper_bills_entered_idx on public.paper_bills(entered_by,bill_date desc);
create index if not exists paper_bills_sold_idx on public.paper_bills(sold_by,bill_date desc);

create table if not exists public.paper_bill_items (
  id uuid primary key default gen_random_uuid(),
  bill_id uuid not null references public.paper_bills(id) on delete restrict,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  category_name_snapshot text not null,
  product_name_snapshot text not null,
  product_code_snapshot text not null,
  color_snapshot text,
  size_snapshot text,
  quantity integer not null check (quantity > 0),
  unit_selling_price numeric(12,2) not null check (unit_selling_price >= 0),
  line_total numeric(12,2) generated always as (quantity * unit_selling_price) stored,
  created_at timestamptz not null default now()
);
create index if not exists paper_bill_items_bill_idx on public.paper_bill_items(bill_id);
create index if not exists paper_bill_items_variant_idx on public.paper_bill_items(variant_id);

-- Cost snapshots are Admin-only, separated from Sales-readable bill lines.
create table if not exists public.paper_bill_item_costs (
  bill_item_id uuid primary key references public.paper_bill_items(id) on delete restrict,
  unit_cost_snapshot numeric(12,2) check (unit_cost_snapshot is null or unit_cost_snapshot >= 0)
);

create table if not exists public.stock_movements (
  id uuid primary key default gen_random_uuid(),
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  bill_id uuid references public.paper_bills(id) on delete restrict,
  movement_type text not null,
  available_delta integer not null default 0,
  damaged_delta integer not null default 0,
  pending_delta integer not null default 0,
  reason text not null,
  notes text,
  performed_by uuid not null references public.profiles(id) on delete restrict,
  created_at timestamptz not null default now()
);
create index if not exists stock_movements_variant_idx on public.stock_movements(variant_id,created_at desc);

-- ---------------------------------------------------------------------------
-- Admin-only cashbook, custom expense categories and refunds
-- ---------------------------------------------------------------------------
create table if not exists public.expense_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_system boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create unique index if not exists expense_categories_name_ci_uq on public.expense_categories(lower(name));

create table if not exists public.cashbook_expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date date not null,
  category_id uuid references public.expense_categories(id) on delete restrict,
  category_snapshot text not null,
  description text not null,
  amount numeric(12,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('Cash','UPI')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create index if not exists cashbook_expenses_date_idx on public.cashbook_expenses(expense_date desc);

create table if not exists public.cashbook_refunds (
  id uuid primary key default gen_random_uuid(),
  refund_date date not null,
  bill_id uuid references public.paper_bills(id) on delete restrict,
  customer_name text,
  reason text not null,
  amount numeric(12,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('Cash','UPI')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  target_role text not null default 'admin' check (target_role in ('admin','sales','all')),
  target_user_id uuid references public.profiles(id),
  related_bill_id uuid references public.paper_bills(id),
  related_variant_id uuid references public.product_variants(id),
  created_at timestamptz not null default now(),
  read_by uuid[] not null default '{}'::uuid[]
);
create index if not exists notifications_created_idx on public.app_notifications(created_at desc);

create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists activity_log_created_idx on public.activity_log(created_at desc);

-- ---------------------------------------------------------------------------
-- Helper functions. Empty search_path and fully-qualified object names.
-- ---------------------------------------------------------------------------
create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path=''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true
      and coalesce((auth.jwt()->>'iat')::bigint,0) >= p.session_iat_valid_after
  );
$$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.is_active = true and p.role = 'admin'
      and coalesce((auth.jwt()->>'iat')::bigint,0) >= p.session_iat_valid_after
  );
$$;

create or replace function public.current_user_role()
returns text language sql stable security definer set search_path=''
as $$
  select p.role from public.profiles p
  where p.id=auth.uid() and p.is_active=true
    and coalesce((auth.jwt()->>'iat')::bigint,0) >= p.session_iat_valid_after
  limit 1;
$$;

-- One-time bootstrap: only the explicitly registered owner email can claim Admin,
-- and it must be the only Auth user at the moment of bootstrap.
create or replace function public.bootstrap_owner_profile(p_full_name text, p_username text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid := auth.uid(); v_email text;
begin
  if v_uid is null then raise exception 'Sign in as the owner first'; end if;
  v_email := lower(coalesce(auth.jwt()->>'email',''));
  if v_email <> 'yogisharajan@gmail.com' then raise exception 'Only the registered owner can bootstrap Admin'; end if;
  if exists(select 1 from public.profiles where role='admin') then raise exception 'Owner Admin is already configured'; end if;
  if exists(select 1 from public.profiles) then raise exception 'Profiles already exist; contact the project owner'; end if;
  if (select count(*) from auth.users) <> 1 then raise exception 'Create only the owner Auth user before bootstrapping Admin'; end if;
  if length(trim(coalesce(p_full_name,''))) < 2 then raise exception 'Enter the owner full name'; end if;
  if trim(coalesce(p_username,'')) !~ '^[A-Za-z0-9._-]{3,32}$' then raise exception 'Username must be 3-32 letters, numbers, dot, underscore or hyphen'; end if;
  insert into public.profiles(id,full_name,username,role,is_active)
  values(v_uid,trim(p_full_name),lower(trim(p_username)),'admin',true);
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'owner_admin_bootstrapped','profile',v_uid,jsonb_build_object('email',v_email));
  return v_uid;
end;
$$;

-- Admin-only category, product and variant setup.
create or replace function public.admin_create_category(p_name text,p_code_prefix text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_name,''))='' or trim(coalesce(p_code_prefix,'')) !~ '^[A-Za-z0-9-]{1,12}$' then raise exception 'Valid category name and code prefix required'; end if;
  insert into public.categories(name,code_prefix,created_by)
  values(trim(p_name),upper(trim(p_code_prefix)),auth.uid()) returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'category_created','category',v_id,jsonb_build_object('name',p_name,'code_prefix',upper(p_code_prefix)));
  return v_id;
end;
$$;

create or replace function public.admin_update_category(p_category_id uuid,p_name text,p_code_prefix text,p_is_active boolean)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_name,''))='' or trim(coalesce(p_code_prefix,'')) !~ '^[A-Za-z0-9-]{1,12}$' then raise exception 'Valid category name and code prefix required'; end if;
  update public.categories set name=trim(p_name),code_prefix=upper(trim(p_code_prefix)),is_active=p_is_active,updated_at=now()
  where id=p_category_id;
  if not found then raise exception 'Category not found'; end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'category_updated','category',p_category_id,jsonb_build_object('name',p_name,'code_prefix',p_code_prefix,'is_active',p_is_active));
end;
$$;

create or replace function public.admin_create_product(p_category_id uuid,p_name text,p_product_code text default null,p_notes text default null)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_code text; v_prefix text; v_number bigint;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Product name required'; end if;
  select code_prefix into v_prefix from public.categories where id=p_category_id and is_active=true;
  if v_prefix is null then raise exception 'Active category not found'; end if;
  if nullif(trim(p_product_code),'') is null then
    insert into public.product_code_sequences(category_id,last_number) values(p_category_id,1)
    on conflict(category_id) do update set last_number=product_code_sequences.last_number+1
    returning last_number into v_number;
    v_code:=v_prefix||'-'||lpad(v_number::text,5,'0');
  else
    v_code:=upper(trim(p_product_code));
  end if;
  insert into public.products(category_id,name,product_code,notes,created_by)
  values(p_category_id,trim(p_name),v_code,nullif(trim(p_notes),''),auth.uid()) returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'product_created','product',v_id,jsonb_build_object('product_code',v_code));
  return v_id;
end;
$$;

-- Sales may add a new product under an existing Admin-defined category.
-- This creates the product identity and its first variant; purchase cost remains NULL/Admin-only.
create or replace function public.sales_create_product(
  p_category_id uuid,p_name text,p_color text,p_size text,p_selling_price numeric,
  p_opening_stock integer default 0,p_min_stock integer default 0
) returns jsonb language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_role text:=public.current_user_role();
  v_prefix text; v_number bigint; v_code text; v_product uuid; v_variant uuid;
begin
  if v_role<>'sales' then raise exception 'Sales account required'; end if;
  if trim(coalesce(p_name,''))='' or p_selling_price<0 or p_opening_stock<0 or p_min_stock<0 then
    raise exception 'Valid product name, selling price and non-negative stock/threshold required';
  end if;
  select code_prefix into v_prefix from public.categories where id=p_category_id and is_active=true;
  if v_prefix is null then raise exception 'Choose an existing active Admin-defined category'; end if;
  insert into public.product_code_sequences(category_id,last_number) values(p_category_id,1)
  on conflict(category_id) do update set last_number=product_code_sequences.last_number+1
  returning last_number into v_number;
  v_code:=v_prefix||'-'||lpad(v_number::text,5,'0');
  insert into public.products(category_id,name,product_code,created_by)
  values(p_category_id,trim(p_name),v_code,v_uid) returning id into v_product;
  insert into public.product_variants(product_id,color,size,selling_price,min_stock,stock_on_hand)
  values(v_product,nullif(trim(p_color),''),nullif(trim(p_size),''),p_selling_price,p_min_stock,p_opening_stock)
  returning id into v_variant;
  insert into public.variant_costs(variant_id,purchase_price,updated_by) values(v_variant,null,v_uid);
  if p_opening_stock>0 then
    insert into public.stock_movements(variant_id,movement_type,available_delta,reason,performed_by)
    values(v_variant,'sales_product_opening_stock',p_opening_stock,'New product stock added by Sales',v_uid);
  end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'sales_product_created','product',v_product,jsonb_build_object('product_code',v_code,'variant_id',v_variant));
  insert into public.app_notifications(title,message,target_role,related_variant_id)
  values('New product added by Sales',format('%s added %s under %s (%s). Admin can add procurement details.',(select full_name from public.profiles where id=v_uid),trim(p_name),(select name from public.categories where id=p_category_id),v_code),'admin',v_variant);
  return jsonb_build_object('product_id',v_product,'variant_id',v_variant,'product_code',v_code);
end;
$$;

-- Sales can add another size/colour only to a product they created; product identity/details are immutable to Sales.
create or replace function public.sales_add_variant_to_own_product(
  p_product_id uuid,p_color text,p_size text,p_selling_price numeric,
  p_opening_stock integer default 0,p_min_stock integer default 0
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_uid uuid:=auth.uid(); v_variant uuid;
begin
  if public.current_user_role()<>'sales' then raise exception 'Sales account required'; end if;
  if p_selling_price<0 or p_opening_stock<0 or p_min_stock<0 then raise exception 'Price, stock and threshold must be non-negative'; end if;
  if not exists(select 1 from public.products where id=p_product_id and created_by=v_uid and is_archived=false) then
    raise exception 'Sales may add variants only to a product they created';
  end if;
  insert into public.product_variants(product_id,color,size,selling_price,min_stock,stock_on_hand)
  values(p_product_id,nullif(trim(p_color),''),nullif(trim(p_size),''),p_selling_price,p_min_stock,p_opening_stock)
  returning id into v_variant;
  insert into public.variant_costs(variant_id,purchase_price,updated_by) values(v_variant,null,v_uid);
  if p_opening_stock>0 then
    insert into public.stock_movements(variant_id,movement_type,available_delta,reason,performed_by)
    values(v_variant,'sales_new_variant_stock',p_opening_stock,'New variant stock added by Sales',v_uid);
  end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'sales_variant_created','product_variant',v_variant,jsonb_build_object('product_id',p_product_id,'opening_stock',p_opening_stock));
  return v_variant;
end;
$$;

create or replace function public.admin_update_product(
  p_product_id uuid,p_category_id uuid,p_name text,p_product_code text,p_notes text default null
) returns void language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_name,''))='' or trim(coalesce(p_product_code,''))='' then raise exception 'Product name and code required'; end if;
  if not exists(select 1 from public.categories where id=p_category_id and is_active=true) then raise exception 'Active category not found'; end if;
  update public.products set category_id=p_category_id,name=trim(p_name),product_code=upper(trim(p_product_code)),
    notes=nullif(trim(p_notes),''),updated_at=now()
  where id=p_product_id and is_archived=false;
  if not found then raise exception 'Active product not found'; end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'product_updated','product',p_product_id,jsonb_build_object('name',p_name,'product_code',upper(p_product_code),'category_id',p_category_id));
end;
$$;

create or replace function public.admin_archive_product(p_product_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  update public.products set is_archived=true,archived_at=now(),updated_at=now() where id=p_product_id and is_archived=false;
  if not found then raise exception 'Active product not found'; end if;
  update public.product_variants set is_active=false,archived_at=now(),updated_at=now() where product_id=p_product_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'product_archived','product',p_product_id,'{}'::jsonb);
end;
$$;

create or replace function public.admin_create_variant(
  p_product_id uuid,p_color text,p_size text,p_selling_price numeric,p_min_stock integer,
  p_opening_stock integer default 0,p_purchase_price numeric default null
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_selling_price<0 or p_min_stock<0 or p_opening_stock<0 or (p_purchase_price is not null and p_purchase_price<0) then raise exception 'Price, threshold and stock must be non-negative'; end if;
  if not exists(select 1 from public.products where id=p_product_id and is_archived=false) then raise exception 'Active product not found'; end if;
  insert into public.product_variants(product_id,color,size,selling_price,min_stock,stock_on_hand)
  values(p_product_id,nullif(trim(p_color),''),nullif(trim(p_size),''),p_selling_price,p_min_stock,p_opening_stock)
  returning id into v_id;
  insert into public.variant_costs(variant_id,purchase_price,updated_by)
  values(v_id,p_purchase_price,auth.uid());
  if p_opening_stock>0 then
    insert into public.stock_movements(variant_id,movement_type,available_delta,reason,performed_by)
    values(v_id,'opening_stock',p_opening_stock,'Opening inventory',auth.uid());
  end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'variant_created','product_variant',v_id,jsonb_build_object('opening_stock',p_opening_stock));
  return v_id;
end;
$$;

create or replace function public.admin_update_variant(
  p_variant_id uuid,p_selling_price numeric,p_min_stock integer,p_purchase_price numeric default null
) returns void language plpgsql security definer set search_path=''
as $$
declare v_old numeric(12,2);
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_selling_price<0 or p_min_stock<0 or (p_purchase_price is not null and p_purchase_price<0) then raise exception 'Price and threshold must be non-negative'; end if;
  update public.product_variants set selling_price=p_selling_price,min_stock=p_min_stock,updated_at=now() where id=p_variant_id and is_active=true;
  if not found then raise exception 'Active variant not found'; end if;
  if p_purchase_price is not null then
    select purchase_price into v_old from public.variant_costs where variant_id=p_variant_id for update;
    insert into public.variant_costs(variant_id,purchase_price,cost_history,updated_by,updated_at)
    values(p_variant_id,p_purchase_price,jsonb_build_array(jsonb_build_object('old_price',v_old,'new_price',p_purchase_price,'changed_at',now(),'changed_by',auth.uid())),auth.uid(),now())
    on conflict(variant_id) do update set purchase_price=excluded.purchase_price,
      cost_history=variant_costs.cost_history||excluded.cost_history,updated_by=auth.uid(),updated_at=now();
  end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'variant_updated','product_variant',p_variant_id,jsonb_build_object('selling_price',p_selling_price,'min_stock',p_min_stock,'purchase_price_updated',p_purchase_price is not null));
end;
$$;

-- Sales and Admin may add stock only to an already-created active variant.
-- Only Admin may provide/update the purchase price.
create or replace function public.add_existing_variant_stock(
  p_variant_id uuid,p_quantity integer,p_reason text,p_notes text default null,p_new_purchase_price numeric default null
) returns void language plpgsql security definer set search_path=''
as $$
declare v_role text; v_current_cost numeric(12,2);
begin
  v_role:=public.current_user_role();
  if v_role is null then raise exception 'Active account required'; end if;
  if p_quantity is null or p_quantity<=0 or trim(coalesce(p_reason,''))='' then raise exception 'Positive quantity and reason are required'; end if;
  if p_new_purchase_price is not null and v_role<>'admin' then raise exception 'Only Admin can enter purchase price'; end if;
  perform 1 from public.product_variants where id=p_variant_id and is_active=true for update;
  if not found then raise exception 'Active product variant not found'; end if;
  update public.product_variants set stock_on_hand=stock_on_hand+p_quantity,updated_at=now() where id=p_variant_id;
  if p_new_purchase_price is not null then
    if p_new_purchase_price<0 then raise exception 'Purchase price cannot be negative'; end if;
    select purchase_price into v_current_cost from public.variant_costs where variant_id=p_variant_id for update;
    insert into public.variant_costs(variant_id,purchase_price,cost_history,updated_by,updated_at)
    values(p_variant_id,p_new_purchase_price,jsonb_build_array(jsonb_build_object('old_price',v_current_cost,'new_price',p_new_purchase_price,'changed_at',now(),'changed_by',auth.uid(),'reason',p_reason)),auth.uid(),now())
    on conflict(variant_id) do update set purchase_price=excluded.purchase_price,cost_history=variant_costs.cost_history||excluded.cost_history,updated_by=auth.uid(),updated_at=now();
  end if;
  insert into public.stock_movements(variant_id,movement_type,available_delta,reason,notes,performed_by)
  values(p_variant_id,'stock_addition',p_quantity,trim(p_reason),nullif(trim(p_notes),''),auth.uid());
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'stock_added','product_variant',p_variant_id,jsonb_build_object('quantity',p_quantity,'reason',p_reason));
  if v_role='sales' then
    insert into public.app_notifications(title,message,target_role,related_variant_id)
    values('Stock added by Sales',format('%s added %s pieces. Reason: %s.',(select full_name from public.profiles where id=auth.uid()),p_quantity,p_reason),'admin',p_variant_id);
  end if;
end;
$$;

create or replace function public.admin_adjust_variant_stock(
  p_variant_id uuid,p_stock_type text,p_delta integer,p_reason text
) returns void language plpgsql security definer set search_path=''
as $$
declare v public.product_variants%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_delta=0 or trim(coalesce(p_reason,''))='' then raise exception 'Non-zero adjustment and reason are required'; end if;
  select * into v from public.product_variants where id=p_variant_id for update;
  if not found then raise exception 'Variant not found'; end if;
  if p_stock_type='saleable' then
    if v.stock_on_hand+p_delta<0 then raise exception 'Adjustment would create negative saleable stock'; end if;
    update public.product_variants set stock_on_hand=stock_on_hand+p_delta,updated_at=now() where id=p_variant_id;
    insert into public.stock_movements(variant_id,movement_type,available_delta,reason,performed_by) values(p_variant_id,'admin_stock_correction',p_delta,p_reason,auth.uid());
  elsif p_stock_type='damaged' then
    if v.damaged_qty+p_delta<0 then raise exception 'Adjustment would create negative damaged stock'; end if;
    update public.product_variants set damaged_qty=damaged_qty+p_delta,updated_at=now() where id=p_variant_id;
    insert into public.stock_movements(variant_id,movement_type,damaged_delta,reason,performed_by) values(p_variant_id,'admin_damaged_stock_correction',p_delta,p_reason,auth.uid());
  elsif p_stock_type='pending' then
    if v.pending_inspection_qty+p_delta<0 then raise exception 'Adjustment would create negative pending stock'; end if;
    update public.product_variants set pending_inspection_qty=pending_inspection_qty+p_delta,updated_at=now() where id=p_variant_id;
    insert into public.stock_movements(variant_id,movement_type,pending_delta,reason,performed_by) values(p_variant_id,'admin_pending_stock_correction',p_delta,p_reason,auth.uid());
  else raise exception 'Stock type must be saleable, damaged or pending'; end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'stock_corrected','product_variant',p_variant_id,jsonb_build_object('stock_type',p_stock_type,'delta',p_delta,'reason',p_reason));
end;
$$;

-- Atomic paper-bill entry: validates stock under row locks, deducts quantities,
-- writes bill and item rows, and logs notifications in one transaction.
create or replace function public.record_paper_bill(
  p_physical_bill_number text,p_bill_date date,p_customer_name text,p_customer_phone text,
  p_sold_by uuid,p_items jsonb,p_final_amount numeric,p_cash_amount numeric,p_upi_amount numeric,
  p_admin_discount numeric default 0,p_amount_overridden boolean default false
) returns uuid language plpgsql security definer set search_path=''
as $$
declare
  v_uid uuid:=auth.uid(); v_role text:=public.current_user_role(); v_customer uuid;
  v_phone_norm text; v_bill uuid; v_item jsonb; v_variant public.product_variants%rowtype;
  v_product public.products%rowtype; v_category public.categories%rowtype; v_item_id uuid;
  v_qty integer; v_price numeric(12,2); v_subtotal numeric(12,2):=0; r record;
begin
  if v_uid is null or v_role is null then raise exception 'Active authenticated account required'; end if;
  if v_role='sales' and p_sold_by<>v_uid then raise exception 'Sales can record only their own bills'; end if;
  if trim(coalesce(p_physical_bill_number,''))='' or trim(coalesce(p_customer_name,''))='' or p_bill_date is null then raise exception 'Bill number, date and customer name are required'; end if;
  if p_final_amount<0 or p_cash_amount<0 or p_upi_amount<0 or abs((p_cash_amount+p_upi_amount)-p_final_amount)>0.01 then raise exception 'Cash plus UPI must equal final bill amount'; end if;
  if coalesce(p_admin_discount,0)<0 or (v_role<>'admin' and coalesce(p_admin_discount,0)<>0) then raise exception 'Only Admin may apply an Admin discount'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one bill item is required'; end if;

  -- Normalize/link customer. Purchase history remains Admin-only by RLS.
  if nullif(trim(p_customer_phone),'') is not null then
    v_phone_norm:=regexp_replace(p_customer_phone,'[^0-9]','','g');
    if length(v_phone_norm)<7 or length(v_phone_norm)>15 then raise exception 'Invalid customer phone'; end if;
    insert into public.customers(phone,phone_normalized) values(trim(p_customer_phone),v_phone_norm)
      on conflict(phone_normalized) do update set phone=excluded.phone returning id into v_customer;
  else
    insert into public.customers DEFAULT VALUES returning id into v_customer;
  end if;
  insert into public.customer_aliases(customer_id,customer_name,normalized_name)
  values(v_customer,trim(p_customer_name),lower(trim(p_customer_name)))
  on conflict(customer_id,normalized_name) do nothing;

  -- Lock variants in stable order and validate aggregate quantity to prevent overselling.
  for r in
    select (x.value->>'variantId')::uuid as variant_id, sum((x.value->>'quantity')::integer)::integer as qty
    from jsonb_array_elements(p_items) x group by 1 order by 1
  loop
    select * into v_variant from public.product_variants where id=r.variant_id and is_active=true for update;
    if not found then raise exception 'An item refers to an inactive or missing variant'; end if;
    if r.qty<=0 or v_variant.stock_on_hand<r.qty then raise exception 'Insufficient saleable stock for variant %',r.variant_id; end if;
  end loop;

  insert into public.paper_bills(physical_bill_number,bill_date,customer_id,customer_name_snapshot,customer_phone_snapshot,sold_by,entered_by,final_amount,cash_amount,upi_amount,amount_overridden,updated_by)
  values(trim(p_physical_bill_number),p_bill_date,v_customer,trim(p_customer_name),nullif(trim(p_customer_phone),''),p_sold_by,v_uid,p_final_amount,p_cash_amount,p_upi_amount,coalesce(p_amount_overridden,false),v_uid)
  returning id into v_bill;

  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::integer; v_price:=(v_item->>'unitPrice')::numeric;
    if v_qty<=0 or v_price<0 then raise exception 'Invalid quantity or unit price'; end if;
    select * into v_variant from public.product_variants where id=(v_item->>'variantId')::uuid and is_active=true;
    select * into v_product from public.products where id=v_variant.product_id and is_archived=false;
    select * into v_category from public.categories where id=v_product.category_id and is_active=true;
    if v_product.id is null or v_category.id is null then raise exception 'Product or category is inactive'; end if;
    insert into public.paper_bill_items(bill_id,variant_id,category_name_snapshot,product_name_snapshot,product_code_snapshot,color_snapshot,size_snapshot,quantity,unit_selling_price)
    values(v_bill,v_variant.id,v_category.name,v_product.name,v_product.product_code,v_variant.color,v_variant.size,v_qty,v_price)
    returning id into v_item_id;
    insert into public.paper_bill_item_costs(bill_item_id,unit_cost_snapshot)
    select v_item_id,vc.purchase_price from public.variant_costs vc where vc.variant_id=v_variant.id;
    update public.product_variants set stock_on_hand=stock_on_hand-v_qty,updated_at=now() where id=v_variant.id;
    insert into public.stock_movements(variant_id,bill_id,movement_type,available_delta,reason,performed_by)
    values(v_variant.id,v_bill,'paper_bill_sale',-v_qty,'Physical bill '||trim(p_physical_bill_number),v_uid);
    v_subtotal:=v_subtotal+(v_qty*v_price);
    if v_variant.stock_on_hand-v_qty<=v_variant.min_stock then
      insert into public.app_notifications(title,message,target_role,related_bill_id,related_variant_id)
      values('Low stock alert',format('%s / %s / %s has %s saleable pieces remaining.',v_product.name,coalesce(v_variant.color,'No colour'),coalesce(v_variant.size,'No size'),v_variant.stock_on_hand-v_qty),'admin',v_bill,v_variant.id);
    end if;
  end loop;

  if coalesce(p_admin_discount,0)>v_subtotal then raise exception 'Admin discount cannot exceed bill subtotal'; end if;
  update public.paper_bills set subtotal=v_subtotal,admin_discount=coalesce(p_admin_discount,0),amount_overridden=(coalesce(p_amount_overridden,false) or abs(p_final_amount-(v_subtotal-coalesce(p_admin_discount,0)))>0.01) where id=v_bill;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(v_uid,'paper_bill_entered','paper_bill',v_bill,jsonb_build_object('physical_bill_number',p_physical_bill_number,'final_amount',p_final_amount));
  insert into public.app_notifications(title,message,target_role,related_bill_id)
  values('New paper bill entered',format('Bill %s · %s · ₹%s · %s',trim(p_physical_bill_number),trim(p_customer_name),p_final_amount,case when p_cash_amount>0 and p_upi_amount>0 then 'Cash + UPI' when p_cash_amount>0 then 'Cash' else 'UPI' end),'admin',v_bill);
  return v_bill;
end;
$$;

create or replace function public.admin_cancel_paper_bill(p_bill_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=''
as $$
declare v_bill public.paper_bills%rowtype; r record;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_reason,''))='' then raise exception 'Cancellation reason is required'; end if;
  select * into v_bill from public.paper_bills where id=p_bill_id for update;
  if not found or v_bill.status<>'posted' then raise exception 'Posted bill not found'; end if;
  for r in select variant_id,sum(quantity)::integer qty from public.paper_bill_items where bill_id=p_bill_id group by variant_id order by variant_id loop
    update public.product_variants set stock_on_hand=stock_on_hand+r.qty,updated_at=now() where id=r.variant_id;
    insert into public.stock_movements(variant_id,bill_id,movement_type,available_delta,reason,performed_by)
    values(r.variant_id,p_bill_id,'admin_bill_cancel_stock_restore',r.qty,p_reason,auth.uid());
  end loop;
  update public.paper_bills set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid(),updated_at=now(),updated_by=auth.uid(),
    correction_history=correction_history||jsonb_build_array(jsonb_build_object('action','cancelled','reason',p_reason,'by',auth.uid(),'at',now())) where id=p_bill_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'paper_bill_cancelled','paper_bill',p_bill_id,jsonb_build_object('reason',p_reason));
end;
$$;

create or replace function public.admin_correct_bill_amount(
  p_bill_id uuid,p_final_amount numeric,p_cash_amount numeric,p_upi_amount numeric,p_reason text
) returns void language plpgsql security definer set search_path=''
as $$
declare v_bill public.paper_bills%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_reason,''))='' or p_final_amount<0 or p_cash_amount<0 or p_upi_amount<0 or abs(p_cash_amount+p_upi_amount-p_final_amount)>0.01 then raise exception 'Valid amount, payment split and reason required'; end if;
  select * into v_bill from public.paper_bills where id=p_bill_id for update;
  if not found or v_bill.status<>'posted' then raise exception 'Posted bill not found'; end if;
  update public.paper_bills set final_amount=p_final_amount,cash_amount=p_cash_amount,upi_amount=p_upi_amount,amount_overridden=true,updated_at=now(),updated_by=auth.uid(),
    correction_history=correction_history||jsonb_build_array(jsonb_build_object('action','amount_corrected','reason',p_reason,'before',jsonb_build_object('final_amount',v_bill.final_amount,'cash',v_bill.cash_amount,'upi',v_bill.upi_amount),'after',jsonb_build_object('final_amount',p_final_amount,'cash',p_cash_amount,'upi',p_upi_amount),'by',auth.uid(),'at',now()))
  where id=p_bill_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
  values(auth.uid(),'paper_bill_amount_corrected','paper_bill',p_bill_id,jsonb_build_object('reason',p_reason));
end;
$$;

-- Admin-only cashbook RPCs.
create or replace function public.admin_create_expense_category(p_name text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_name,''))='' then raise exception 'Category name required'; end if;
  insert into public.expense_categories(name,is_system,created_by) values(trim(p_name),false,auth.uid()) returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'expense_category_created','expense_category',v_id,jsonb_build_object('name',p_name));
  return v_id;
end;
$$;

create or replace function public.admin_record_expense(
  p_expense_date date,p_category_id uuid,p_description text,p_amount numeric,p_payment_method text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_category text;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_amount<=0 or trim(coalesce(p_description,''))='' or p_payment_method not in ('Cash','UPI') then raise exception 'Valid description, positive amount and Cash/UPI method required'; end if;
  select name into v_category from public.expense_categories where id=p_category_id and is_active=true;
  if v_category is null then raise exception 'Active expense category not found'; end if;
  insert into public.cashbook_expenses(expense_date,category_id,category_snapshot,description,amount,payment_method,created_by)
  values(p_expense_date,p_category_id,v_category,trim(p_description),p_amount,p_payment_method,auth.uid()) returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'cashbook_expense_recorded','cashbook_expense',v_id,jsonb_build_object('amount',p_amount,'method',p_payment_method));
  return v_id;
end;
$$;

create or replace function public.admin_record_refund(
  p_refund_date date,p_bill_id uuid,p_customer_name text,p_reason text,p_amount numeric,p_payment_method text
) returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_amount<=0 or trim(coalesce(p_reason,''))='' or p_payment_method not in ('Cash','UPI') then raise exception 'Valid refund reason, positive amount and Cash/UPI method required'; end if;
  if p_bill_id is not null and not exists(select 1 from public.paper_bills where id=p_bill_id) then raise exception 'Bill not found'; end if;
  insert into public.cashbook_refunds(refund_date,bill_id,customer_name,reason,amount,payment_method,created_by)
  values(p_refund_date,p_bill_id,nullif(trim(p_customer_name),''),trim(p_reason),p_amount,p_payment_method,auth.uid()) returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details) values(auth.uid(),'cashbook_refund_recorded','cashbook_refund',v_id,jsonb_build_object('amount',p_amount,'method',p_payment_method));
  return v_id;
end;
$$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
  if not public.is_active_user() then raise exception 'Active account required'; end if;
  update public.app_notifications set read_by=array(select distinct unnest(read_by||auth.uid()))
  where id=p_notification_id and (public.is_admin() or target_role in ('sales','all') or target_user_id=auth.uid());
end;
$$;

-- ---------------------------------------------------------------------------
-- RLS policies: explicit drop first, safe to re-run.
-- Direct table writes are revoked; business changes go through audited RPCs.
-- ---------------------------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.variant_costs enable row level security;
alter table public.customers enable row level security;
alter table public.customer_aliases enable row level security;
alter table public.paper_bills enable row level security;
alter table public.paper_bill_items enable row level security;
alter table public.paper_bill_item_costs enable row level security;
alter table public.stock_movements enable row level security;
alter table public.expense_categories enable row level security;
alter table public.cashbook_expenses enable row level security;
alter table public.cashbook_refunds enable row level security;
alter table public.app_notifications enable row level security;
alter table public.activity_log enable row level security;

-- Profiles: Admin can see all; Sales can see only their own profile.
drop policy if exists profiles_select_self_admin on public.profiles;
create policy profiles_select_self_admin on public.profiles for select to authenticated using (public.is_active_user() and (id=auth.uid() or public.is_admin()));

drop policy if exists categories_select_active on public.categories;
create policy categories_select_active on public.categories for select to authenticated using (public.is_active_user() and is_active=true);
drop policy if exists categories_admin_all on public.categories;
create policy categories_admin_all on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists products_select_active on public.products;
create policy products_select_active on public.products for select to authenticated using (public.is_active_user() and is_archived=false);
drop policy if exists products_admin_all on public.products;
create policy products_admin_all on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists variants_select_active on public.product_variants;
create policy variants_select_active on public.product_variants for select to authenticated using (public.is_active_user() and is_active=true);
drop policy if exists variants_admin_all on public.product_variants;
create policy variants_admin_all on public.product_variants for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists variant_costs_admin_only on public.variant_costs;
create policy variant_costs_admin_only on public.variant_costs for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists customers_admin_only on public.customers;
create policy customers_admin_only on public.customers for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists customer_aliases_admin_only on public.customer_aliases;
create policy customer_aliases_admin_only on public.customer_aliases for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists bills_select_own_admin on public.paper_bills;
create policy bills_select_own_admin on public.paper_bills for select to authenticated using (public.is_active_user() and (public.is_admin() or entered_by=auth.uid() or sold_by=auth.uid()));
drop policy if exists bill_items_select_own_admin on public.paper_bill_items;
create policy bill_items_select_own_admin on public.paper_bill_items for select to authenticated using (public.is_active_user() and exists(select 1 from public.paper_bills b where b.id=bill_id and (public.is_admin() or b.entered_by=auth.uid() or b.sold_by=auth.uid())));
drop policy if exists bill_item_costs_admin_only on public.paper_bill_item_costs;
create policy bill_item_costs_admin_only on public.paper_bill_item_costs for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists stock_movements_select_own_admin on public.stock_movements;
create policy stock_movements_select_own_admin on public.stock_movements for select to authenticated using (public.is_active_user() and (public.is_admin() or performed_by=auth.uid()));

drop policy if exists expense_categories_admin_only on public.expense_categories;
create policy expense_categories_admin_only on public.expense_categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists expenses_admin_only on public.cashbook_expenses;
create policy expenses_admin_only on public.cashbook_expenses for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists refunds_admin_only on public.cashbook_refunds;
create policy refunds_admin_only on public.cashbook_refunds for all to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists notifications_select_targeted on public.app_notifications;
create policy notifications_select_targeted on public.app_notifications for select to authenticated using (
  public.is_active_user() and (target_user_id=auth.uid() or target_role='all' or target_role=public.current_user_role())
);
drop policy if exists notifications_admin_update on public.app_notifications;
create policy notifications_admin_update on public.app_notifications for update to authenticated using (public.is_admin()) with check (public.is_admin());

drop policy if exists activity_log_admin_read on public.activity_log;
create policy activity_log_admin_read on public.activity_log for select to authenticated using (public.is_admin());

-- ---------------------------------------------------------------------------
-- Grants: no anonymous access; authenticated table SELECT only.
-- ---------------------------------------------------------------------------
grant usage on schema public to authenticated;
revoke all on public.profiles,public.categories,public.products,public.product_code_sequences,public.product_variants,
  public.variant_costs,public.customers,public.customer_aliases,public.paper_bills,
  public.paper_bill_items,public.paper_bill_item_costs,public.stock_movements,
  public.expense_categories,public.cashbook_expenses,public.cashbook_refunds,
  public.app_notifications,public.activity_log from anon,authenticated;
grant select on public.profiles,public.categories,public.products,public.product_variants,
  public.variant_costs,public.customers,public.customer_aliases,public.paper_bills,
  public.paper_bill_items,public.paper_bill_item_costs,public.stock_movements,
  public.expense_categories,public.cashbook_expenses,public.cashbook_refunds,
  public.app_notifications,public.activity_log to authenticated;

revoke all on function public.is_active_user() from public,anon;
revoke all on function public.is_admin() from public,anon;
revoke all on function public.current_user_role() from public,anon;
revoke all on function public.bootstrap_owner_profile(text,text) from public,anon;
revoke all on function public.admin_create_category(text,text) from public,anon;
revoke all on function public.admin_update_category(uuid,text,text,boolean) from public,anon;
revoke all on function public.admin_create_product(uuid,text,text,text) from public,anon;
revoke all on function public.admin_update_product(uuid,uuid,text,text,text) from public,anon;
revoke all on function public.admin_archive_product(uuid) from public,anon;
revoke all on function public.sales_create_product(uuid,text,text,text,numeric,integer,integer) from public,anon;
revoke all on function public.sales_add_variant_to_own_product(uuid,text,text,numeric,integer,integer) from public,anon;
revoke all on function public.admin_create_variant(uuid,text,text,numeric,integer,integer,numeric) from public,anon;
revoke all on function public.admin_update_variant(uuid,numeric,integer,numeric) from public,anon;
revoke all on function public.add_existing_variant_stock(uuid,integer,text,text,numeric) from public,anon;
revoke all on function public.admin_adjust_variant_stock(uuid,text,integer,text) from public,anon;
revoke all on function public.record_paper_bill(text,date,text,text,uuid,jsonb,numeric,numeric,numeric,numeric,boolean) from public,anon;
revoke all on function public.admin_cancel_paper_bill(uuid,text) from public,anon;
revoke all on function public.admin_correct_bill_amount(uuid,numeric,numeric,numeric,text) from public,anon;
revoke all on function public.admin_create_expense_category(text) from public,anon;
revoke all on function public.admin_record_expense(date,uuid,text,numeric,text) from public,anon;
revoke all on function public.admin_record_refund(date,uuid,text,text,numeric,text) from public,anon;
revoke all on function public.mark_notification_read(uuid) from public,anon;

grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;
grant execute on function public.current_user_role() to authenticated;
grant execute on function public.bootstrap_owner_profile(text,text) to authenticated;
grant execute on function public.admin_create_category(text,text) to authenticated;
grant execute on function public.admin_update_category(uuid,text,text,boolean) to authenticated;
grant execute on function public.admin_create_product(uuid,text,text,text) to authenticated;
grant execute on function public.admin_update_product(uuid,uuid,text,text,text) to authenticated;
grant execute on function public.admin_archive_product(uuid) to authenticated;
grant execute on function public.sales_create_product(uuid,text,text,text,numeric,integer,integer) to authenticated;
grant execute on function public.sales_add_variant_to_own_product(uuid,text,text,numeric,integer,integer) to authenticated;
grant execute on function public.admin_create_variant(uuid,text,text,numeric,integer,integer,numeric) to authenticated;
grant execute on function public.admin_update_variant(uuid,numeric,integer,numeric) to authenticated;
grant execute on function public.add_existing_variant_stock(uuid,integer,text,text,numeric) to authenticated;
grant execute on function public.admin_adjust_variant_stock(uuid,text,integer,text) to authenticated;
grant execute on function public.record_paper_bill(text,date,text,text,uuid,jsonb,numeric,numeric,numeric,numeric,boolean) to authenticated;
grant execute on function public.admin_cancel_paper_bill(uuid,text) to authenticated;
grant execute on function public.admin_correct_bill_amount(uuid,numeric,numeric,numeric,text) to authenticated;
grant execute on function public.admin_create_expense_category(text) to authenticated;
grant execute on function public.admin_record_expense(date,uuid,text,numeric,text) to authenticated;
grant execute on function public.admin_record_refund(date,uuid,text,text,numeric,text) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;

-- Seed the nine agreed categories and standard cashbook categories.
insert into public.categories(name,code_prefix) values
 ('2-piece chudi','2PC'),('3-piece chudi','3PC'),('Tops','TOP'),('Dupatta','DUP'),
 ('Legging','LEG'),('Shawl','SHA'),('Blouse','BLO'),('Saree','SAR'),('Petticoat','PET')
on conflict do nothing;
insert into public.expense_categories(name,is_system) values
 ('Rent',true),('Salary',true),('Electricity',true),('Transport',true),
 ('Packaging',true),('Maintenance',true),('Other',true)
on conflict do nothing;

-- Private product photo bucket. Authenticated active users may read; only Admin may write.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('ananta-product-photos','ananta-product-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];

drop policy if exists ananta_product_photos_read on storage.objects;
create policy ananta_product_photos_read on storage.objects for select to authenticated
using (bucket_id='ananta-product-photos' and public.is_active_user());
drop policy if exists ananta_product_photos_admin_insert on storage.objects;
create policy ananta_product_photos_admin_insert on storage.objects for insert to authenticated
with check (bucket_id='ananta-product-photos' and public.is_admin());
drop policy if exists ananta_product_photos_admin_update on storage.objects;
create policy ananta_product_photos_admin_update on storage.objects for update to authenticated
using (bucket_id='ananta-product-photos' and public.is_admin()) with check (bucket_id='ananta-product-photos' and public.is_admin());
drop policy if exists ananta_product_photos_admin_delete on storage.objects;
create policy ananta_product_photos_admin_delete on storage.objects for delete to authenticated
using (bucket_id='ananta-product-photos' and public.is_admin());

-- Add application tables to Supabase Realtime if publication exists.
do $$
declare t text;
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array['profiles','categories','products','product_variants','paper_bills','paper_bill_items','stock_movements','cashbook_expenses','cashbook_refunds','app_notifications'] loop
      if not exists(
        select 1 from pg_publication_tables
        where pubname='supabase_realtime' and schemaname='public' and tablename=t
      ) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end;
$$;

commit;

-- Verify after execution:
-- select table_name from information_schema.tables where table_schema='public' order by 1;
-- select name,code_prefix from public.categories order by name;
-- select id,email from auth.users;
-- select * from storage.buckets where id='ananta-product-photos';