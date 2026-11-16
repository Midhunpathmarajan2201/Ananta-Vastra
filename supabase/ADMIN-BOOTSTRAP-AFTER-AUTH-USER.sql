-- Run this AFTER creating/confirming the owner's Auth user in Supabase Dashboard.
-- It creates the only Admin profile associated with the existing Auth user.
-- Expected owner email: yogisharajan@gmail.com
-- Change the display name / username literals if desired. Do not put a password here.

insert into public.profiles (id, full_name, username, role, is_active)
select u.id, 'Yogi Sharajan', 'admin', 'admin', true
from auth.users u
where lower(u.email) = 'yogisharajan@gmail.com'
  and u.email_confirmed_at is not null
  and not exists (select 1 from public.profiles where role='admin')
  and not exists (select 1 from public.profiles)
  and (select count(*) from auth.users) = 1
on conflict (id) do nothing;

-- Confirm one Admin profile was created:
select p.id, p.full_name, p.username, p.role, p.is_active, u.email
from public.profiles p join auth.users u on u.id=p.id
where p.role='admin';