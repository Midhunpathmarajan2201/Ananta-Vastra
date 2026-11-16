-- Ananta Vastra: Supabase/PostgreSQL backend foundation
-- Review and test in a fresh Supabase project before using real shop data.
-- Browser demo is NOT connected to this schema. Production client writes must use the RPCs below.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete restrict,
  full_name text not null,
  username text not null unique,
  role text not null default 'sales' check (role in ('admin','sales')),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  deactivated_at timestamptz
);
create unique index if not exists one_ananta_vastra_admin on public.profiles(role) where role='admin';

create or replace function public.is_active_user()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.is_active=true); $$;

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path=public
as $$ select exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin' and p.is_active=true); $$;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  code_prefix text not null,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  check (code_prefix ~ '^[A-Z0-9-]{1,12}$')
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  category_id uuid not null references public.categories(id) on delete restrict,
  name text not null,
  product_code text not null unique,
  notes text,
  photo_url text,
  is_archived boolean not null default false,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  archived_at timestamptz
);

create table if not exists public.product_variants (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete restrict,
  color text,
  size text,
  stock_on_hand integer not null default 0 check (stock_on_hand >= 0),
  damaged_qty integer not null default 0 check (damaged_qty >= 0),
  pending_inspection_qty integer not null default 0 check (pending_inspection_qty >= 0),
  selling_price numeric(12,2) not null check (selling_price >= 0),
  purchase_price numeric(12,2) check (purchase_price is null or purchase_price >= 0),
  min_stock integer not null default 0 check (min_stock >= 0),
  is_active boolean not null default true,
  cost_history jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  archived_at timestamptz
);
create unique index if not exists one_active_variant_combination
  on public.product_variants(product_id, lower(coalesce(color,'')), lower(coalesce(size,'')))
  where is_active=true;

-- A phone number identifies the customer group; aliases preserve all names used on paper bills.
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
  physical_bill_number text not null unique,
  bill_date date not null,
  customer_id uuid references public.customers(id) on delete restrict,
  customer_name_snapshot text not null,
  customer_phone_snapshot text,
  sold_by uuid not null references public.profiles(id) on delete restrict,
  entered_by uuid not null references public.profiles(id) on delete restrict,
  entered_at timestamptz not null default now(),
  subtotal numeric(12,2) not null check (subtotal >= 0),
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
create unique index if not exists paper_bills_physical_number_ci on public.paper_bills(lower(trim(physical_bill_number)));
create index if not exists paper_bills_date_idx on public.paper_bills(bill_date desc);
create index if not exists paper_bills_entered_by_idx on public.paper_bills(entered_by, bill_date desc);
create index if not exists paper_bills_sold_by_idx on public.paper_bills(sold_by, bill_date desc);

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
  unit_cost_snapshot numeric(12,2),
  line_total numeric(12,2) generated always as (quantity * unit_selling_price) stored,
  created_at timestamptz not null default now()
);
create index if not exists paper_bill_items_bill_idx on public.paper_bill_items(bill_id);

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
create index if not exists stock_movements_variant_idx on public.stock_movements(variant_id, created_at desc);

create table if not exists public.cashbook_expenses (
  id uuid primary key default gen_random_uuid(),
  expense_date date not null,
  category text not null,
  description text not null,
  amount numeric(12,2) not null check (amount > 0),
  payment_method text not null check (payment_method in ('Cash','UPI')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  supplier_name text not null,
  phone text,
  email text,
  address text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.supplier_invoices (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid not null references public.suppliers(id) on delete restrict,
  invoice_number text not null,
  invoice_date date not null,
  invoice_total numeric(12,2) not null check (invoice_total >= 0),
  amount_paid numeric(12,2) not null default 0 check (amount_paid >= 0),
  description text,
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now(),
  unique(supplier_id, invoice_number),
  check (amount_paid <= invoice_total)
);
create table if not exists public.supplier_invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.supplier_invoices(id) on delete restrict,
  variant_id uuid not null references public.product_variants(id) on delete restrict,
  quantity integer not null check (quantity > 0),
  unit_purchase_price numeric(12,2) not null check (unit_purchase_price >= 0)
);
create table if not exists public.supplier_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.supplier_invoices(id) on delete restrict,
  payment_date date not null,
  amount numeric(12,2) not null check (amount > 0),
  reference text,
  recorded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  target_role text not null default 'admin' check (target_role in ('admin','sales','all')),
  related_bill_id uuid references public.paper_bills(id),
  related_variant_id uuid references public.product_variants(id),
  created_at timestamptz not null default now(),
  read_by uuid[] not null default '{}'
);
create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

-- Account gating: every RLS policy checks that the profile is active.
alter table public.profiles enable row level security;
alter table public.categories enable row level security;
alter table public.products enable row level security;
alter table public.product_variants enable row level security;
alter table public.customers enable row level security;
alter table public.customer_aliases enable row level security;
alter table public.paper_bills enable row level security;
alter table public.paper_bill_items enable row level security;
alter table public.stock_movements enable row level security;
alter table public.cashbook_expenses enable row level security;
alter table public.suppliers enable row level security;
alter table public.supplier_invoices enable row level security;
alter table public.supplier_invoice_items enable row level security;
alter table public.supplier_payments enable row level security;
alter table public.app_notifications enable row level security;
alter table public.activity_log enable row level security;

drop policy if exists profile_read_self_or_admin on public.profiles;
drop policy if exists profile_read_self_or_admin on public.profiles;
create policy profile_read_self_or_admin on public.profiles for select to authenticated using (public.is_active_user() and (id=auth.uid() or public.is_admin()));
drop policy if exists profile_admin_update on public.profiles;
drop policy if exists profile_admin_update on public.profiles;
create policy profile_admin_update on public.profiles for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- Shared read access for active users; only Admin can create/update/archive catalogue data.
drop policy if exists categories_read_active on public.categories;
create policy categories_read_active on public.categories for select to authenticated using (public.is_active_user() and is_active=true);
drop policy if exists categories_admin_all on public.categories;
create policy categories_admin_all on public.categories for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists products_read_active on public.products;
create policy products_read_active on public.products for select to authenticated using (public.is_active_user() and is_archived=false);
drop policy if exists products_admin_all on public.products;
create policy products_admin_all on public.products for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists variants_read_active on public.product_variants;
create policy variants_read_active on public.product_variants for select to authenticated using (public.is_active_user() and is_active=true);
drop policy if exists variants_admin_all on public.product_variants;
create policy variants_admin_all on public.product_variants for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Customer purchase history is Admin-only. Sales customer aliases should be resolved through a limited RPC.
drop policy if exists customers_admin_all on public.customers;
create policy customers_admin_all on public.customers for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists customer_aliases_admin_all on public.customer_aliases;
create policy customer_aliases_admin_all on public.customer_aliases for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Sales can view their own records; Admin can view all. Bills are inserted/corrected only through RPCs.
drop policy if exists paper_bills_read on public.paper_bills;
create policy paper_bills_read on public.paper_bills for select to authenticated using (public.is_active_user() and (public.is_admin() or entered_by=auth.uid() or sold_by=auth.uid()));
drop policy if exists paper_bill_items_read on public.paper_bill_items;
create policy paper_bill_items_read on public.paper_bill_items for select to authenticated using (public.is_active_user() and exists(select 1 from public.paper_bills b where b.id=bill_id and (public.is_admin() or b.entered_by=auth.uid() or b.sold_by=auth.uid())));
drop policy if exists stock_movements_read on public.stock_movements;
create policy stock_movements_read on public.stock_movements for select to authenticated using (public.is_active_user() and (public.is_admin() or performed_by=auth.uid()));

-- Financial and supplier records are Admin-only.
drop policy if exists cashbook_admin_all on public.cashbook_expenses;
create policy cashbook_admin_all on public.cashbook_expenses for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists suppliers_admin_all on public.suppliers;
create policy suppliers_admin_all on public.suppliers for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists supplier_invoices_admin_all on public.supplier_invoices;
create policy supplier_invoices_admin_all on public.supplier_invoices for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists supplier_invoice_items_admin_all on public.supplier_invoice_items;
create policy supplier_invoice_items_admin_all on public.supplier_invoice_items for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists supplier_payments_admin_all on public.supplier_payments;
create policy supplier_payments_admin_all on public.supplier_payments for all to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists notifications_admin_read on public.app_notifications;
create policy notifications_admin_read on public.app_notifications for select to authenticated using (public.is_active_user() and (public.is_admin() or target_role in ('sales','all')));
drop policy if exists notifications_admin_update on public.app_notifications;
create policy notifications_admin_update on public.app_notifications for update to authenticated using (public.is_admin()) with check (public.is_admin());
drop policy if exists activity_admin_read on public.activity_log;
create policy activity_admin_read on public.activity_log for select to authenticated using (public.is_admin());

-- The client must not update stock quantities or write bills directly. Use these transactional RPCs.
create or replace function public.record_paper_bill(
  p_physical_bill_number text,
  p_bill_date date,
  p_customer_name text,
  p_customer_phone text,
  p_sold_by uuid,
  p_items jsonb,
  p_final_amount numeric,
  p_cash_amount numeric,
  p_upi_amount numeric,
  p_admin_discount numeric default 0,
  p_amount_overridden boolean default false
) returns uuid
language plpgsql security definer set search_path=public
as $$
declare
  v_user uuid := auth.uid();
  v_role text;
  v_customer uuid;
  v_phone_norm text;
  v_bill uuid;
  v_item jsonb;
  v_variant public.product_variants%rowtype;
  v_product public.products%rowtype;
  v_category public.categories%rowtype;
  v_qty integer;
  v_price numeric(12,2);
  v_subtotal numeric(12,2) := 0;
begin
  select role into v_role from public.profiles where id=v_user and is_active=true;
  if v_role is null then raise exception 'Active account required'; end if;
  if v_role='sales' and p_sold_by <> v_user then raise exception 'Sales may record only their own sales'; end if;
  if coalesce(trim(p_physical_bill_number),'')='' or coalesce(trim(p_customer_name),'')='' then raise exception 'Bill number and customer name are required'; end if;
  if p_admin_discount <> 0 and v_role <> 'admin' then raise exception 'Only Admin can apply discounts'; end if;
  if p_final_amount < 0 or p_cash_amount < 0 or p_upi_amount < 0 or abs((p_cash_amount+p_upi_amount)-p_final_amount) > 0.01 then raise exception 'Payment split must equal final bill amount'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one item is required'; end if;
  if p_customer_phone is not null and trim(p_customer_phone)<>'' then
    v_phone_norm := regexp_replace(p_customer_phone, '\D', '', 'g');
    if length(v_phone_norm)<7 or length(v_phone_norm)>15 then raise exception 'Invalid customer phone number'; end if;
    insert into public.customers(phone,phone_normalized) values (p_customer_phone,v_phone_norm)
      on conflict(phone_normalized) do update set phone=excluded.phone returning id into v_customer;
    insert into public.customer_aliases(customer_id,customer_name,normalized_name)
      values(v_customer,trim(p_customer_name),lower(trim(p_customer_name))) on conflict(customer_id,normalized_name) do nothing;
  end if;
  insert into public.paper_bills(physical_bill_number,bill_date,customer_id,customer_name_snapshot,customer_phone_snapshot,sold_by,entered_by,subtotal,admin_discount,final_amount,cash_amount,upi_amount,amount_overridden,updated_by)
  values(trim(p_physical_bill_number),p_bill_date,v_customer,trim(p_customer_name),nullif(trim(p_customer_phone),''),p_sold_by,v_user,0,p_admin_discount,p_final_amount,p_cash_amount,p_upi_amount,p_amount_overridden,v_user)
  returning id into v_bill;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty := (v_item->>'quantity')::integer;
    v_price := (v_item->>'unitPrice')::numeric;
    if v_qty<=0 or v_price<0 then raise exception 'Invalid item quantity or price'; end if;
    select * into v_variant from public.product_variants where id=(v_item->>'variantId')::uuid and is_active=true for update;
    if not found then raise exception 'Product variant is inactive or unavailable'; end if;
    if v_variant.stock_on_hand < v_qty then raise exception 'Insufficient stock for variant %',v_variant.id; end if;
    select * into v_product from public.products where id=v_variant.product_id and is_archived=false;
    select * into v_category from public.categories where id=v_product.category_id;
    update public.product_variants set stock_on_hand=stock_on_hand-v_qty where id=v_variant.id;
    if (v_variant.stock_on_hand-v_qty) <= v_variant.min_stock then
      insert into public.app_notifications(title,message,target_role,related_variant_id)
        values('Low stock alert',format('%s / %s has %s pieces remaining (threshold %s).',coalesce(v_product.name,'Product'),coalesce(v_variant.color,'No colour')||' / '||coalesce(v_variant.size,'No size'),v_variant.stock_on_hand-v_qty,v_variant.min_stock),'admin',v_variant.id);
    end if;
    insert into public.paper_bill_items(bill_id,variant_id,category_name_snapshot,product_name_snapshot,product_code_snapshot,color_snapshot,size_snapshot,quantity,unit_selling_price,unit_cost_snapshot)
      values(v_bill,v_variant.id,v_category.name,v_product.name,v_product.product_code,v_variant.color,v_variant.size,v_qty,v_price,v_variant.purchase_price);
    insert into public.stock_movements(variant_id,bill_id,movement_type,available_delta,reason,performed_by)
      values(v_variant.id,v_bill,'paper_bill_sale',-v_qty,'Physical bill '||trim(p_physical_bill_number),v_user);
    v_subtotal := v_subtotal + (v_qty*v_price);
  end loop;
  if p_admin_discount < 0 or p_admin_discount > v_subtotal then raise exception 'Invalid Admin discount'; end if;
  update public.paper_bills set subtotal=v_subtotal where id=v_bill;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(v_user,'paper_bill_entered','paper_bill',v_bill,jsonb_build_object('physical_bill_number',p_physical_bill_number,'final_amount',p_final_amount));
  insert into public.app_notifications(title,message,target_role,related_bill_id)
    values('New paper bill entered',format('Paper bill %s · %s · ₹%s. Sold by %s; entered by %s.',trim(p_physical_bill_number),trim(p_customer_name),p_final_amount,(select full_name from public.profiles where id=p_sold_by),(select full_name from public.profiles where id=v_user)),'admin',v_bill);
  return v_bill;
end $$;

create or replace function public.add_existing_variant_stock(
  p_variant_id uuid, p_quantity integer, p_reason text, p_notes text default null, p_new_purchase_price numeric default null
) returns void language plpgsql security definer set search_path=public
as $$
declare v_role text; v_variant public.product_variants%rowtype;
begin
  select role into v_role from public.profiles where id=auth.uid() and is_active=true;
  if v_role is null then raise exception 'Active account required'; end if;
  if p_quantity<=0 or coalesce(trim(p_reason),'')='' then raise exception 'Positive quantity and reason are required'; end if;
  if p_new_purchase_price is not null and v_role<>'admin' then raise exception 'Only Admin can enter purchase price'; end if;
  select * into v_variant from public.product_variants where id=p_variant_id and is_active=true for update;
  if not found then raise exception 'Variant not found'; end if;
  update public.product_variants set stock_on_hand=stock_on_hand+p_quantity,
    purchase_price=coalesce(p_new_purchase_price,purchase_price),
    cost_history=case when p_new_purchase_price is null then cost_history else cost_history||jsonb_build_array(jsonb_build_object('previous_price',purchase_price,'new_price',p_new_purchase_price,'changed_at',now(),'changed_by',auth.uid())) end
    where id=p_variant_id;
  insert into public.stock_movements(variant_id,movement_type,available_delta,reason,notes,performed_by)
    values(p_variant_id,'stock_addition',p_quantity,p_reason,p_notes,auth.uid());
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'stock_added','product_variant',p_variant_id,jsonb_build_object('quantity',p_quantity,'reason',p_reason));
  if v_role='sales' then
    insert into public.app_notifications(title,message,target_role,related_variant_id)
      values('Stock added by Sales',format('%s added %s pieces. Reason: %s.',(select full_name from public.profiles where id=auth.uid()),p_quantity,p_reason),'admin',p_variant_id);
  end if;
end $$;

-- Admin-only bill correction. Every stock delta and bill-line replacement is one DB transaction.
create or replace function public.admin_correct_paper_bill(
  p_bill_id uuid,
  p_items jsonb,
  p_final_amount numeric,
  p_cash_amount numeric,
  p_upi_amount numeric,
  p_admin_discount numeric,
  p_reason text,
  p_return_condition text default 'saleable'
) returns void language plpgsql security definer set search_path=public
as $$
declare
  v_bill public.paper_bills%rowtype;
  v_row record;
  v_variant public.product_variants%rowtype;
  v_product public.products%rowtype;
  v_category public.categories%rowtype;
  v_item jsonb;
  v_qty integer;
  v_price numeric(12,2);
  v_cost numeric(12,2);
  v_subtotal numeric(12,2):=0;
  v_before jsonb;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Correction reason is required'; end if;
  if p_return_condition not in ('saleable','damaged','pending') then raise exception 'Invalid return condition'; end if;
  select * into v_bill from public.paper_bills where id=p_bill_id for update;
  if not found or v_bill.status<>'posted' then raise exception 'Posted bill not found'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one item must remain on the corrected bill'; end if;
  if p_final_amount<0 or p_cash_amount<0 or p_upi_amount<0 or abs((p_cash_amount+p_upi_amount)-p_final_amount)>0.01 then raise exception 'Payment split must equal final amount'; end if;
  v_before:=jsonb_build_object('paper_bill_number',v_bill.physical_bill_number,'final_amount',v_bill.final_amount,'items',(select coalesce(jsonb_agg(jsonb_build_object('variant_id',variant_id,'quantity',quantity,'unit_price',unit_selling_price)), '[]'::jsonb) from public.paper_bill_items where bill_id=p_bill_id));

  for v_row in
    with old_q as (select variant_id,sum(quantity)::integer qty from public.paper_bill_items where bill_id=p_bill_id group by variant_id),
    new_q as (select (x.value->>'variantId')::uuid variant_id,sum((x.value->>'quantity')::integer)::integer qty from jsonb_array_elements(p_items) x group by 1)
    select coalesce(o.variant_id,n.variant_id) variant_id,coalesce(o.qty,0) old_qty,coalesce(n.qty,0) new_qty
    from old_q o full join new_q n on n.variant_id=o.variant_id
  loop
    select * into v_variant from public.product_variants where id=v_row.variant_id for update;
    if not found then raise exception 'A bill variant no longer exists'; end if;
    if v_row.new_qty>v_row.old_qty then
      if v_variant.stock_on_hand < (v_row.new_qty-v_row.old_qty) then raise exception 'Insufficient stock to apply correction'; end if;
      update public.product_variants set stock_on_hand=stock_on_hand-(v_row.new_qty-v_row.old_qty) where id=v_variant.id;
      insert into public.stock_movements(variant_id,bill_id,movement_type,available_delta,reason,performed_by)
        values(v_variant.id,p_bill_id,'admin_bill_correction_sale',-(v_row.new_qty-v_row.old_qty),p_reason,auth.uid());
    elsif v_row.new_qty<v_row.old_qty then
      v_qty:=v_row.old_qty-v_row.new_qty;
      if p_return_condition='saleable' then
        update public.product_variants set stock_on_hand=stock_on_hand+v_qty where id=v_variant.id;
        insert into public.stock_movements(variant_id,bill_id,movement_type,available_delta,reason,performed_by)
          values(v_variant.id,p_bill_id,'admin_bill_correction_return',v_qty,p_reason,auth.uid());
      elsif p_return_condition='damaged' then
        update public.product_variants set damaged_qty=damaged_qty+v_qty where id=v_variant.id;
        insert into public.stock_movements(variant_id,bill_id,movement_type,damaged_delta,reason,performed_by)
          values(v_variant.id,p_bill_id,'admin_bill_correction_damaged',v_qty,p_reason,auth.uid());
      else
        update public.product_variants set pending_inspection_qty=pending_inspection_qty+v_qty where id=v_variant.id;
        insert into public.stock_movements(variant_id,bill_id,movement_type,pending_delta,reason,performed_by)
          values(v_variant.id,p_bill_id,'admin_bill_correction_pending',v_qty,p_reason,auth.uid());
      end if;
    end if;
  end loop;

  delete from public.paper_bill_items where bill_id=p_bill_id;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::integer; v_price:=(v_item->>'unitPrice')::numeric;
    if v_qty<=0 or v_price<0 then raise exception 'Invalid corrected item quantity or price'; end if;
    select * into v_variant from public.product_variants where id=(v_item->>'variantId')::uuid;
    select * into v_product from public.products where id=v_variant.product_id;
    select * into v_category from public.categories where id=v_product.category_id;
    if v_item ? 'costSnapshot' then v_cost:=nullif(v_item->>'costSnapshot','')::numeric; else v_cost:=v_variant.purchase_price; end if;
    insert into public.paper_bill_items(bill_id,variant_id,category_name_snapshot,product_name_snapshot,product_code_snapshot,color_snapshot,size_snapshot,quantity,unit_selling_price,unit_cost_snapshot)
      values(p_bill_id,v_variant.id,v_category.name,v_product.name,v_product.product_code,v_variant.color,v_variant.size,v_qty,v_price,v_cost);
    v_subtotal:=v_subtotal+(v_qty*v_price);
  end loop;
  if p_admin_discount<0 or p_admin_discount>v_subtotal then raise exception 'Invalid Admin discount'; end if;
  update public.paper_bills set subtotal=v_subtotal,admin_discount=p_admin_discount,final_amount=p_final_amount,
    cash_amount=p_cash_amount,upi_amount=p_upi_amount,amount_overridden=(abs(p_final_amount-(v_subtotal-p_admin_discount))>0.01),
    updated_at=now(),updated_by=auth.uid(),
    correction_history=correction_history||jsonb_build_array(jsonb_build_object('reason',p_reason,'return_condition',p_return_condition,'before',v_before,'after',jsonb_build_object('final_amount',p_final_amount,'subtotal',v_subtotal),'by',auth.uid(),'at',now()))
    where id=p_bill_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'paper_bill_corrected','paper_bill',p_bill_id,jsonb_build_object('reason',p_reason,'return_condition',p_return_condition,'final_amount',p_final_amount));
end $$;

create or replace function public.admin_cancel_paper_bill(p_bill_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public
as $$
declare v_bill public.paper_bills%rowtype; r record;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if coalesce(trim(p_reason),'')='' then raise exception 'Cancellation reason is required'; end if;
  select * into v_bill from public.paper_bills where id=p_bill_id for update;
  if not found or v_bill.status<>'posted' then raise exception 'Posted bill not found'; end if;
  for r in select variant_id,sum(quantity)::integer qty from public.paper_bill_items where bill_id=p_bill_id group by variant_id loop
    update public.product_variants set stock_on_hand=stock_on_hand+r.qty where id=r.variant_id;
    insert into public.stock_movements(variant_id,bill_id,movement_type,available_delta,reason,performed_by)
      values(r.variant_id,p_bill_id,'admin_bill_cancel_stock_restore',r.qty,p_reason,auth.uid());
  end loop;
  update public.paper_bills set status='cancelled',cancelled_at=now(),cancelled_by=auth.uid(),updated_at=now(),updated_by=auth.uid(),
    correction_history=correction_history||jsonb_build_array(jsonb_build_object('reason',p_reason,'action','cancelled','by',auth.uid(),'at',now())) where id=p_bill_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'paper_bill_cancelled','paper_bill',p_bill_id,jsonb_build_object('reason',p_reason));
end $$;

create or replace function public.admin_adjust_variant_stock(p_variant_id uuid,p_delta integer,p_reason text)
returns void language plpgsql security definer set search_path=public
as $$
declare v public.product_variants%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_delta=0 or coalesce(trim(p_reason),'')='' then raise exception 'Non-zero adjustment and reason are required'; end if;
  select * into v from public.product_variants where id=p_variant_id for update;
  if not found then raise exception 'Variant not found'; end if;
  if v.stock_on_hand+p_delta<0 then raise exception 'Adjustment would create negative stock'; end if;
  update public.product_variants set stock_on_hand=stock_on_hand+p_delta where id=p_variant_id;
  insert into public.stock_movements(variant_id,movement_type,available_delta,reason,performed_by)
    values(p_variant_id,'admin_stock_correction',p_delta,p_reason,auth.uid());
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'stock_corrected','product_variant',p_variant_id,jsonb_build_object('delta',p_delta,'reason',p_reason));
end $$;

-- Supplier invoice receiving is atomic: invoice, stock receipts, procurement price and history commit together.
create or replace function public.receive_supplier_invoice(
  p_supplier_id uuid, p_invoice_number text, p_invoice_date date, p_invoice_total numeric,
  p_amount_paid numeric, p_description text, p_items jsonb
) returns uuid language plpgsql security definer set search_path=public
as $$
declare
  v_invoice uuid; v_item jsonb; v_variant public.product_variants%rowtype;
  v_qty integer; v_price numeric(12,2); v_line_total numeric(12,2);
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if coalesce(trim(p_invoice_number),'')='' or p_invoice_total<0 or p_amount_paid<0 or p_amount_paid>p_invoice_total then
    raise exception 'Invalid supplier invoice details'; end if;
  if jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'At least one stock line is required'; end if;
  if not exists(select 1 from public.suppliers where id=p_supplier_id and is_active=true) then raise exception 'Active supplier not found'; end if;
  insert into public.supplier_invoices(supplier_id,invoice_number,invoice_date,invoice_total,amount_paid,description,created_by)
    values(p_supplier_id,trim(p_invoice_number),p_invoice_date,p_invoice_total,p_amount_paid,p_description,auth.uid()) returning id into v_invoice;
  for v_item in select value from jsonb_array_elements(p_items) loop
    v_qty:=(v_item->>'quantity')::integer; v_price:=(v_item->>'unitPurchasePrice')::numeric;
    if v_qty<=0 or v_price<0 then raise exception 'Invalid purchased quantity or cost'; end if;
    select * into v_variant from public.product_variants where id=(v_item->>'variantId')::uuid and is_active=true for update;
    if not found then raise exception 'Purchased product variant is unavailable'; end if;
    update public.product_variants set stock_on_hand=stock_on_hand+v_qty,purchase_price=v_price,
      cost_history=cost_history||jsonb_build_array(jsonb_build_object('previous_price',purchase_price,'new_price',v_price,'quantity',v_qty,'supplier_invoice_id',v_invoice,'changed_at',now(),'changed_by',auth.uid()))
      where id=v_variant.id;
    insert into public.supplier_invoice_items(invoice_id,variant_id,quantity,unit_purchase_price)
      values(v_invoice,v_variant.id,v_qty,v_price);
    insert into public.stock_movements(variant_id,movement_type,available_delta,reason,notes,performed_by)
      values(v_variant.id,'supplier_invoice_receipt',v_qty,'Supplier invoice received',trim(p_invoice_number),auth.uid());
  end loop;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'supplier_invoice_received','supplier_invoice',v_invoice,jsonb_build_object('invoice_number',p_invoice_number,'invoice_total',p_invoice_total));
  return v_invoice;
end $$;

create or replace function public.record_supplier_payment(
  p_invoice_id uuid, p_payment_date date, p_amount numeric, p_reference text default null
) returns uuid language plpgsql security definer set search_path=public
as $$
declare v_invoice public.supplier_invoices%rowtype; v_payment uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_amount<=0 then raise exception 'Payment must be positive'; end if;
  select * into v_invoice from public.supplier_invoices where id=p_invoice_id for update;
  if not found then raise exception 'Supplier invoice not found'; end if;
  if v_invoice.amount_paid+p_amount>v_invoice.invoice_total then raise exception 'Payment exceeds invoice outstanding'; end if;
  insert into public.supplier_payments(invoice_id,payment_date,amount,reference,recorded_by)
    values(p_invoice_id,p_payment_date,p_amount,p_reference,auth.uid()) returning id into v_payment;
  update public.supplier_invoices set amount_paid=amount_paid+p_amount where id=p_invoice_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'supplier_payment_recorded','supplier_invoice',p_invoice_id,jsonb_build_object('payment_id',v_payment,'amount',p_amount));
  return v_payment;
end $$;

revoke all on function public.record_paper_bill(text,date,text,text,uuid,jsonb,numeric,numeric,numeric,numeric,boolean) from public;
revoke all on function public.add_existing_variant_stock(uuid,integer,text,text,numeric) from public;
revoke all on function public.admin_correct_paper_bill(uuid,jsonb,numeric,numeric,numeric,numeric,text,text) from public;
revoke all on function public.admin_cancel_paper_bill(uuid,text) from public;
revoke all on function public.admin_adjust_variant_stock(uuid,integer,text) from public;
revoke all on function public.receive_supplier_invoice(uuid,text,date,numeric,numeric,text,jsonb) from public;
revoke all on function public.record_supplier_payment(uuid,date,numeric,text) from public;
grant execute on function public.record_paper_bill(text,date,text,text,uuid,jsonb,numeric,numeric,numeric,numeric,boolean) to authenticated;
grant execute on function public.add_existing_variant_stock(uuid,integer,text,text,numeric) to authenticated;
grant execute on function public.admin_correct_paper_bill(uuid,jsonb,numeric,numeric,numeric,numeric,text,text) to authenticated;
grant execute on function public.admin_cancel_paper_bill(uuid,text) to authenticated;
grant execute on function public.admin_adjust_variant_stock(uuid,integer,text) to authenticated;
grant execute on function public.receive_supplier_invoice(uuid,text,date,numeric,numeric,text,jsonb) to authenticated;
grant execute on function public.record_supplier_payment(uuid,date,numeric,text) to authenticated;

grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- IMPORTANT production tasks not automated by this SQL:
-- 1. Provision the single Admin profile and Sales accounts through a trusted server/Edge Function.
-- 2. Never expose the service_role key in the browser.
-- 3. Use an Edge Function for immediate employee deactivation + global session revocation.
-- 4. Route every write through the transactional RPCs; do not write stock fields from the browser.
-- 5. Implement Admin category/product/variant creation RPCs and audited supplier/cashbook writes.
-- 6. Add private product-photo storage with Admin upload and authenticated read policies.
-- 7. Configure realtime for the relevant tables and test it with separate Admin/Sales users.
-- 8. Configure push delivery, backups and a tested restore procedure.
-- 9. Run a full RLS/security test matrix before importing real business data.


-- =============================================================================
-- PRODUCTION COMPLETION LAYER (2026-11-16)
-- This file is the single SQL Editor script. Run it once in a fresh Supabase
-- project, or rerun safely after the original schema has already been applied.
-- It deliberately does not create Auth users or store passwords.
-- =============================================================================

-- Case-insensitive uniqueness for human-entered identifiers.
create unique index if not exists profiles_username_ci on public.profiles(lower(trim(username)));
create unique index if not exists categories_name_ci on public.categories(lower(trim(name)));
create unique index if not exists products_code_ci on public.products(lower(trim(product_code)));

-- The original profile update policy allowed broad direct profile edits. Remove
-- it: profile lifecycle is now performed through narrowly scoped RPCs.
drop policy if exists profile_admin_update on public.profiles;

-- Ensure all existing policies can be safely recreated on subsequent runs.
drop policy if exists categories_read_active on public.categories;
drop policy if exists categories_admin_all on public.categories;
drop policy if exists products_read_active on public.products;
drop policy if exists products_admin_all on public.products;
drop policy if exists variants_read_active on public.product_variants;
drop policy if exists variants_admin_all on public.product_variants;
drop policy if exists customers_admin_all on public.customers;
drop policy if exists customer_aliases_admin_all on public.customer_aliases;
drop policy if exists paper_bills_read on public.paper_bills;
drop policy if exists paper_bill_items_read on public.paper_bill_items;
drop policy if exists stock_movements_read on public.stock_movements;
drop policy if exists cashbook_admin_all on public.cashbook_expenses;
drop policy if exists suppliers_admin_all on public.suppliers;
drop policy if exists supplier_invoices_admin_all on public.supplier_invoices;
drop policy if exists supplier_invoice_items_admin_all on public.supplier_invoice_items;
drop policy if exists supplier_payments_admin_all on public.supplier_payments;
drop policy if exists notifications_admin_read on public.app_notifications;
drop policy if exists notifications_admin_update on public.app_notifications;
drop policy if exists activity_admin_read on public.activity_log;

create policy categories_read_active on public.categories for select to authenticated
  using (public.is_active_user() and is_active=true);
create policy categories_admin_all on public.categories for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy products_read_active on public.products for select to authenticated
  using (public.is_active_user() and is_archived=false);
create policy products_admin_all on public.products for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy variants_read_active on public.product_variants for select to authenticated
  using (public.is_active_user() and is_active=true);
create policy variants_admin_all on public.product_variants for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy customers_admin_all on public.customers for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy customer_aliases_admin_all on public.customer_aliases for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy paper_bills_read on public.paper_bills for select to authenticated
  using (public.is_active_user() and (public.is_admin() or entered_by=auth.uid() or sold_by=auth.uid()));
create policy paper_bill_items_read on public.paper_bill_items for select to authenticated
  using (public.is_active_user() and exists(
    select 1 from public.paper_bills b where b.id=bill_id
    and (public.is_admin() or b.entered_by=auth.uid() or b.sold_by=auth.uid())
  ));
create policy stock_movements_read on public.stock_movements for select to authenticated
  using (public.is_active_user() and (public.is_admin() or performed_by=auth.uid()));
create policy cashbook_admin_all on public.cashbook_expenses for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy suppliers_admin_all on public.suppliers for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy supplier_invoices_admin_all on public.supplier_invoices for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy supplier_invoice_items_admin_all on public.supplier_invoice_items for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy supplier_payments_admin_all on public.supplier_payments for all to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy notifications_admin_read on public.app_notifications for select to authenticated
  using (public.is_active_user() and (public.is_admin() or target_role in ('sales','all')));
create policy notifications_admin_update on public.app_notifications for update to authenticated
  using (public.is_admin()) with check (public.is_admin());
create policy activity_admin_read on public.activity_log for select to authenticated
  using (public.is_admin());

-- Revoke broad table privileges. The browser receives read-only access and all
-- writes go through the checked, transactional functions below.
revoke all on all tables in schema public from anon, authenticated;
grant select on public.profiles, public.categories, public.products,
  public.customers, public.customer_aliases, public.paper_bills,
  public.stock_movements, public.cashbook_expenses, public.suppliers,
  public.supplier_invoices, public.supplier_invoice_items, public.supplier_payments,
  public.app_notifications, public.activity_log to authenticated;
grant select (id, product_id, color, size, stock_on_hand, damaged_qty,
  pending_inspection_qty, selling_price, min_stock, is_active, created_at, archived_at)
  on public.product_variants to authenticated;
grant select (id, bill_id, variant_id, category_name_snapshot, product_name_snapshot,
  product_code_snapshot, color_snapshot, size_snapshot, quantity,
  unit_selling_price, line_total, created_at)
  on public.paper_bill_items to authenticated;

-- Admins need financial values through a dedicated RPC; Sales must never be
-- able to select procurement prices or historical cost snapshots.
create or replace function public.admin_variant_financials()
returns table (
  variant_id uuid, product_id uuid, purchase_price numeric,
  cost_history jsonb, selling_price numeric, stock_on_hand integer,
  invested_value numeric, potential_sales_value numeric
)
language plpgsql stable security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  return query
    select v.id, v.product_id, v.purchase_price, v.cost_history, v.selling_price,
      v.stock_on_hand,
      case when v.purchase_price is null then null
           else v.stock_on_hand * v.purchase_price end,
      v.stock_on_hand * v.selling_price
    from public.product_variants v
    where v.is_active=true;
end $$;

-- Admin-only catalogue management. Products and variants are never hard-deleted.
create or replace function public.admin_create_category(p_name text,p_prefix text)
returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_name,''))='' or upper(trim(coalesce(p_prefix,''))) !~ '^[A-Z0-9-]{1,12}$'
    then raise exception 'Valid category name and prefix are required'; end if;
  insert into public.categories(name,code_prefix,created_by)
    values(trim(p_name),upper(trim(p_prefix)),auth.uid()) returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'category_created','category',v_id,jsonb_build_object('name',p_name,'prefix',p_prefix));
  return v_id;
end $$;

create or replace function public.admin_archive_category(p_category_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if exists(select 1 from public.products where category_id=p_category_id and is_archived=false)
    then raise exception 'Move or archive all active products before archiving this category'; end if;
  update public.categories set is_active=false where id=p_category_id;
  if not found then raise exception 'Category not found'; end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id)
    values(auth.uid(),'category_archived','category',p_category_id);
end $$;

create or replace function public.admin_create_product(
  p_category_id uuid,p_name text,p_product_code text,p_notes text default null
) returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_id uuid; v_prefix text;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_name,''))='' or trim(coalesce(p_product_code,''))='' then
    raise exception 'Product name and product code are required'; end if;
  select code_prefix into v_prefix from public.categories
    where id=p_category_id and is_active=true;
  if not found then raise exception 'Active category not found'; end if;
  if upper(trim(p_product_code)) not like upper(v_prefix)||'%' then
    raise exception 'Product code must begin with category prefix '||v_prefix; end if;
  insert into public.products(category_id,name,product_code,notes,created_by)
    values(p_category_id,trim(p_name),upper(trim(p_product_code)),p_notes,auth.uid())
    returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'product_created','product',v_id,jsonb_build_object('product_code',p_product_code));
  return v_id;
end $$;

create or replace function public.admin_create_variant(
  p_product_id uuid,p_color text,p_size text,p_selling_price numeric,p_min_stock integer default 0
) returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_selling_price<0 or p_min_stock<0 then raise exception 'Price and threshold cannot be negative'; end if;
  if not exists(select 1 from public.products where id=p_product_id and is_archived=false) then
    raise exception 'Active product not found'; end if;
  insert into public.product_variants(product_id,color,size,selling_price,min_stock)
    values(p_product_id,nullif(trim(p_color),''),nullif(trim(p_size),''),p_selling_price,p_min_stock)
    returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'variant_created','product_variant',v_id,
      jsonb_build_object('color',p_color,'size',p_size,'selling_price',p_selling_price));
  return v_id;
end $$;

create or replace function public.admin_update_variant_pricing(
  p_variant_id uuid,p_selling_price numeric,p_purchase_price numeric
) returns void language plpgsql security definer set search_path=public,pg_temp
as $$
declare v public.product_variants%rowtype;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_selling_price<0 or (p_purchase_price is not null and p_purchase_price<0)
    then raise exception 'Prices cannot be negative'; end if;
  select * into v from public.product_variants where id=p_variant_id for update;
  if not found then raise exception 'Variant not found'; end if;
  update public.product_variants set selling_price=p_selling_price,
    purchase_price=p_purchase_price,
    cost_history=case when p_purchase_price is distinct from v.purchase_price
      then cost_history||jsonb_build_array(jsonb_build_object(
        'previous_price',v.purchase_price,'new_price',p_purchase_price,
        'changed_at',now(),'changed_by',auth.uid()))
      else cost_history end
    where id=p_variant_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'variant_pricing_updated','product_variant',p_variant_id,
      jsonb_build_object('selling_price',p_selling_price,'purchase_price_changed',
        p_purchase_price is distinct from v.purchase_price));
end $$;

create or replace function public.admin_set_variant_low_stock(p_variant_id uuid,p_min_stock integer)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_min_stock<0 then raise exception 'Threshold cannot be negative'; end if;
  update public.product_variants set min_stock=p_min_stock where id=p_variant_id;
  if not found then raise exception 'Variant not found'; end if;
end $$;

create or replace function public.admin_archive_product(p_product_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  update public.products set is_archived=true,archived_at=now() where id=p_product_id;
  if not found then raise exception 'Product not found'; end if;
  update public.product_variants set is_active=false,archived_at=now() where product_id=p_product_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id)
    values(auth.uid(),'product_archived','product',p_product_id);
end $$;

-- Auth users are created in Supabase Auth first. This RPC attaches an existing
-- Auth UUID to a Sales profile; it never accepts or stores a password.
create or replace function public.admin_add_sales_profile(
  p_auth_user_id uuid,p_full_name text,p_username text
) returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_full_name,''))='' or trim(coalesce(p_username,''))='' then
    raise exception 'Employee name and username are required'; end if;
  if not exists(select 1 from auth.users where id=p_auth_user_id) then
    raise exception 'Create the employee in Supabase Auth before adding the profile'; end if;
  insert into public.profiles(id,full_name,username,role,is_active)
    values(p_auth_user_id,trim(p_full_name),trim(p_username),'sales',true);
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'sales_profile_created','profile',p_auth_user_id,jsonb_build_object('username',p_username));
  return p_auth_user_id;
end $$;

create or replace function public.admin_set_sales_active(p_profile_id uuid,p_active boolean)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if exists(select 1 from public.profiles where id=p_profile_id and role='admin') then
    raise exception 'The owner Admin account cannot be deactivated here'; end if;
  update public.profiles set is_active=p_active,
    deactivated_at=case when p_active then null else now() end
    where id=p_profile_id and role='sales';
  if not found then raise exception 'Sales profile not found'; end if;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),case when p_active then 'sales_reactivated' else 'sales_deactivated' end,
      'profile',p_profile_id,jsonb_build_object('is_active',p_active));
end $$;

-- Cashbook expense entry. Bill collections are generated from posted bills below.
create or replace function public.admin_record_cashbook_expense(
  p_expense_date date,p_category text,p_description text,p_amount numeric,p_payment_method text
) returns uuid language plpgsql security definer set search_path=public,pg_temp
as $$
declare v_id uuid;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if trim(coalesce(p_category,''))='' or trim(coalesce(p_description,''))='' or p_amount<=0
    or p_payment_method not in ('Cash','UPI') then raise exception 'Invalid expense details'; end if;
  insert into public.cashbook_expenses(expense_date,category,description,amount,payment_method,created_by)
    values(p_expense_date,trim(p_category),trim(p_description),p_amount,p_payment_method,auth.uid())
    returning id into v_id;
  insert into public.activity_log(actor_id,action,entity_type,entity_id,details)
    values(auth.uid(),'cashbook_expense_recorded','cashbook_expense',v_id,
      jsonb_build_object('amount',p_amount,'payment_method',p_payment_method));
  return v_id;
end $$;

create or replace view public.admin_cashbook_entries
with (security_invoker=true) as
  select b.id as source_id,b.bill_date as entry_date,'Bill collection'::text as entry_type,
    b.physical_bill_number as reference,b.customer_name_snapshot as description,
    b.cash_amount as cash_amount,b.upi_amount as upi_amount,0::numeric as expense_amount
  from public.paper_bills b where b.status='posted'
  union all
  select e.id,e.expense_date,'Expense',null,e.category||' — '||e.description,
    case when e.payment_method='Cash' then 0::numeric else 0::numeric end,
    case when e.payment_method='UPI' then 0::numeric else 0::numeric end,
    e.amount
  from public.cashbook_expenses e;
grant select on public.admin_cashbook_entries to authenticated;

create or replace function public.admin_dashboard_summary(p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp
as $
declare v jsonb;
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Valid report dates required'; end if;
  select jsonb_build_object(
    'bill_count',(select count(*) from public.paper_bills b where b.status='posted' and b.bill_date between p_from and p_to),
    'sales_value',(select coalesce(sum(b.final_amount),0) from public.paper_bills b where b.status='posted' and b.bill_date between p_from and p_to),
    'cash_collected',(select coalesce(sum(x.cash_amount),0) from public.paper_bills x where x.status='posted' and x.bill_date between p_from and p_to),
    'upi_collected',(select coalesce(sum(x.upi_amount),0) from public.paper_bills x where x.status='posted' and x.bill_date between p_from and p_to),
    'pieces_sold',(select coalesce(sum(i.quantity),0) from public.paper_bill_items i join public.paper_bills x on x.id=i.bill_id where x.status='posted' and x.bill_date between p_from and p_to),
    'low_stock_variants',(select count(*) from public.product_variants v where v.is_active=true and v.stock_on_hand<=v.min_stock),
    'available_pieces',(select coalesce(sum(v.stock_on_hand),0) from public.product_variants v where v.is_active=true),
    'expense_total',(select coalesce(sum(e.amount),0) from public.cashbook_expenses e where e.expense_date between p_from and p_to)
  ) into v;
  return v;
end $;

create or replace function public.sales_dashboard_summary(p_from date,p_to date)
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp
as $$
declare v jsonb;
begin
  if not public.is_active_user() then raise exception 'Active account required'; end if;
  if public.is_admin() then raise exception 'Use the Admin dashboard summary'; end if;
  if p_from is null or p_to is null or p_from>p_to then raise exception 'Valid report dates required'; end if;
  select jsonb_build_object(
    'bill_count',count(distinct b.id),
    'sales_value',coalesce(sum(distinct b.final_amount),0),
    'pieces_sold',coalesce((select sum(i.quantity) from public.paper_bill_items i join public.paper_bills x on x.id=i.bill_id where x.entered_by=auth.uid() and x.status='posted' and x.bill_date between p_from and p_to),0)
  ) into v
  from public.paper_bills b
  where b.entered_by=auth.uid() and b.status='posted' and b.bill_date between p_from and p_to;
  return v;
end $$;

create or replace function public.admin_top_selling_products(p_from date,p_to date,p_limit integer default 10)
returns table(product_name text,product_code text,pieces_sold bigint)
language plpgsql stable security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_admin() then raise exception 'Admin permission required'; end if;
  if p_from is null or p_to is null or p_from>p_to or p_limit<1 or p_limit>100
    then raise exception 'Invalid report range or limit'; end if;
  return query
    select i.product_name_snapshot,i.product_code_snapshot,sum(i.quantity)::bigint
    from public.paper_bill_items i join public.paper_bills b on b.id=i.bill_id
    where b.status='posted' and b.bill_date between p_from and p_to
    group by i.product_name_snapshot,i.product_code_snapshot
    order by sum(i.quantity) desc limit p_limit;
end $$;

create or replace function public.mark_notification_read(p_notification_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp
as $$
begin
  if not public.is_active_user() then raise exception 'Active account required'; end if;
  update public.app_notifications
    set read_by=array(select distinct x from unnest(read_by||array[auth.uid()]) x)
    where id=p_notification_id
      and (public.is_admin() or target_role in ('sales','all'));
  if not found then raise exception 'Notification not found or not available'; end if;
end $$;

-- Private product image bucket. Storage policies preserve the same Admin/Sales split.
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('product-photos','product-photos',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,
  allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists product_photos_authenticated_read on storage.objects;
create policy product_photos_authenticated_read on storage.objects for select to authenticated
  using (bucket_id='product-photos' and public.is_active_user());
drop policy if exists product_photos_admin_insert on storage.objects;
create policy product_photos_admin_insert on storage.objects for insert to authenticated
  with check (bucket_id='product-photos' and public.is_admin());
drop policy if exists product_photos_admin_update on storage.objects;
create policy product_photos_admin_update on storage.objects for update to authenticated
  using (bucket_id='product-photos' and public.is_admin())
  with check (bucket_id='product-photos' and public.is_admin());
drop policy if exists product_photos_admin_delete on storage.objects;
create policy product_photos_admin_delete on storage.objects for delete to authenticated
  using (bucket_id='product-photos' and public.is_admin());

-- Initial category catalogue. These are safe defaults and can be renamed by Admin.
insert into public.categories(name,code_prefix,is_active)
values
 ('2-piece chudi','2PC-',true),('3-piece chudi','3PC-',true),('Tops','TOP-',true),
 ('Dupatta','DUP-',true),('Legging','LEG-',true),('Shawl','SHW-',true),
 ('Blouse','BLO-',true),('Saree','SAR-',true),('Petticoat','PET-',true)
on conflict(name) do nothing;

-- Restrict function execution to signed-in users. Each function performs its own
-- role check; no anonymous browser session can execute business operations.
revoke all on function public.admin_variant_financials() from public,anon;
revoke all on function public.admin_create_category(text,text) from public,anon;
revoke all on function public.admin_archive_category(uuid) from public,anon;
revoke all on function public.admin_create_product(uuid,text,text,text) from public,anon;
revoke all on function public.admin_create_variant(uuid,text,text,numeric,integer) from public,anon;
revoke all on function public.admin_update_variant_pricing(uuid,numeric,numeric) from public,anon;
revoke all on function public.admin_set_variant_low_stock(uuid,integer) from public,anon;
revoke all on function public.admin_archive_product(uuid) from public,anon;
revoke all on function public.admin_add_sales_profile(uuid,text,text) from public,anon;
revoke all on function public.admin_set_sales_active(uuid,boolean) from public,anon;
revoke all on function public.admin_record_cashbook_expense(date,text,text,numeric,text) from public,anon;
revoke all on function public.admin_dashboard_summary(date,date) from public,anon;
revoke all on function public.sales_dashboard_summary(date,date) from public,anon;
revoke all on function public.admin_top_selling_products(date,date,integer) from public,anon;
revoke all on function public.mark_notification_read(uuid) from public,anon;
grant execute on function public.admin_variant_financials() to authenticated;
grant execute on function public.admin_create_category(text,text) to authenticated;
grant execute on function public.admin_archive_category(uuid) to authenticated;
grant execute on function public.admin_create_product(uuid,text,text,text) to authenticated;
grant execute on function public.admin_create_variant(uuid,text,text,numeric,integer) to authenticated;
grant execute on function public.admin_update_variant_pricing(uuid,numeric,numeric) to authenticated;
grant execute on function public.admin_set_variant_low_stock(uuid,integer) to authenticated;
grant execute on function public.admin_archive_product(uuid) to authenticated;
grant execute on function public.admin_add_sales_profile(uuid,text,text) to authenticated;
grant execute on function public.admin_set_sales_active(uuid,boolean) to authenticated;
grant execute on function public.admin_record_cashbook_expense(date,text,text,numeric,text) to authenticated;
grant execute on function public.admin_dashboard_summary(date,date) to authenticated;
grant execute on function public.sales_dashboard_summary(date,date) to authenticated;
grant execute on function public.admin_top_selling_products(date,date,integer) to authenticated;
grant execute on function public.mark_notification_read(uuid) to authenticated;

grant execute on function public.is_active_user() to authenticated;
grant execute on function public.is_admin() to authenticated;

-- Revoke direct write access even if project default privileges were broadened.
revoke insert,update,delete,truncate,references,trigger on all tables in schema public from anon,authenticated;

-- Re-grant only SELECT to authenticated; all business mutations are RPC-only.
grant select on public.profiles,public.categories,public.products,public.customers,
  public.customer_aliases,public.paper_bills,public.stock_movements,
  public.cashbook_expenses,public.suppliers,public.supplier_invoices,
  public.supplier_invoice_items,public.supplier_payments,public.app_notifications,
  public.activity_log,public.admin_cashbook_entries to authenticated;
grant select (id,product_id,color,size,stock_on_hand,damaged_qty,pending_inspection_qty,
  selling_price,min_stock,is_active,created_at,archived_at)
  on public.product_variants to authenticated;
grant select (id,bill_id,variant_id,category_name_snapshot,product_name_snapshot,
  product_code_snapshot,color_snapshot,size_snapshot,quantity,unit_selling_price,line_total,created_at)
  on public.paper_bill_items to authenticated;

-- Add operational tables to Supabase Realtime if the publication is available.
do $$
declare t text;
begin
  if exists(select 1 from pg_publication where pubname='supabase_realtime') then
    foreach t in array array['categories','products','product_variants','paper_bills',
      'paper_bill_items','stock_movements','app_notifications','profiles'] loop
      if not exists(
        select 1 from pg_publication_tables
        where pubname='supabase_realtime' and schemaname='public' and tablename=t
      ) then
        execute format('alter publication supabase_realtime add table public.%I',t);
      end if;
    end loop;
  end if;
end $$;

-- =============================================================================
-- FIRST-OWNER BOOTSTRAP (run manually after creating the owner in Supabase Auth)
-- 1. Dashboard > Authentication > Users > Add user; enter owner's email/password.
-- 2. Copy that Auth user's UUID.
-- 3. Replace the two placeholders below and run this INSERT once in SQL Editor.
--    Passwords are managed only by Supabase Auth; never add them to this SQL file.
--
-- insert into public.profiles(id,full_name,username,role,is_active)
-- values ('AUTH_USER_UUID_HERE','Shop Owner','admin','admin',true);
--
-- Sales accounts: create each employee in Authentication first, then sign in as
-- Admin and call admin_add_sales_profile(existing_auth_uuid, full_name, username).
-- Deactivation: call admin_set_sales_active(profile_uuid,false); this immediately
-- blocks DB access through RLS, even while an old access token still exists.
-- For global refresh-token revocation, deploy a trusted Edge Function using the
-- server-only service-role secret; never put that secret in browser code.
-- =============================================================================
