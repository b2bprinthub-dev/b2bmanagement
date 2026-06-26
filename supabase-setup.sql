-- ============================================================
-- B2B Print Hub — Supabase Setup Script
-- Run this in Supabase SQL Editor to restore all tables,
-- columns, policies, and settings after a wipe.
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- 1. CORE TABLES (created by the app on first run via Supabase
--    dashboard — listed here for reference / manual restore)
-- ────────────────────────────────────────────────────────────

-- settings
create table if not exists settings (
  id         bigint generated always as identity primary key,
  key        text unique not null,
  value      jsonb,
  updated_at timestamptz default now()
);

-- clients
create table if not exists clients (
  id         bigint generated always as identity primary key,
  name       text,
  email      text,
  phone      text,
  address    text,
  notes      text,
  created_at timestamptz default now()
);

-- invoices
create table if not exists invoices (
  id         bigint generated always as identity primary key,
  cid        bigint references clients(id),
  date       text,
  due        text,
  status     text,
  items      jsonb,
  sub        numeric,
  disc       numeric,
  tax        numeric,
  grand      numeric,
  notes      text,
  created_at timestamptz default now()
);

-- estimates
create table if not exists estimates (
  id          bigint generated always as identity primary key,
  cid         bigint references clients(id),
  date        text,
  status      text,
  items       jsonb,
  sub         numeric,
  disc        numeric,
  tax         numeric,
  grand       numeric,
  description jsonb,
  notes       text,
  created_at  timestamptz default now()
);

-- transactions
create table if not exists transactions (
  id         bigint generated always as identity primary key,
  type       text,
  amount     numeric,
  method     text,
  client_id  bigint references clients(id),
  invoice_id bigint references invoices(id),
  notes      text,
  created_at timestamptz default now()
);

-- expenses
create table if not exists expenses (
  id          bigint generated always as identity primary key,
  date        text,
  type        text,
  category    text,
  vendor      text,
  client_id   bigint references clients(id),
  amount      numeric,
  method      text,
  reference   text,
  notes       text,
  from_drawer boolean default false,     -- true = paid from cash register during shift
  shift_id    text,                      -- links to pos_shifts.id
  created_by  text,
  created_at  timestamptz default now()
);

-- pos_shifts
create table if not exists pos_shifts (
  id                     bigint generated always as identity primary key,
  cashier_id             text,           -- app user id (text, not uuid)
  cashier_name           text,
  status                 text,           -- open | closed | pending_approval
  opening_amount         numeric,
  closing_amount_counted numeric,
  expected_cash          numeric,
  over_short             numeric,
  notes                  text,
  sales_count            integer,
  sales_total            numeric,
  cash_sales             numeric,
  card_sales             numeric,
  other_sales            numeric,
  approved_by            text,
  approved_at            timestamptz,
  opened_at              timestamptz,
  closed_at              timestamptz
);

-- activity_log
create table if not exists activity_log (
  id         bigint generated always as identity primary key,
  username   text,
  action     text,
  module     text,
  details    text,
  created_at timestamptz default now()
);

-- app_users
create table if not exists app_users (
  id         bigint generated always as identity primary key,
  name       text,
  email      text unique,
  role       text,
  pin        text,
  avatar     text,
  created_at timestamptz default now()
);

-- messages
create table if not exists messages (
  id          bigint generated always as identity primary key,
  sender_id   bigint references app_users(id),
  receiver_id bigint references app_users(id),
  content     text,
  read        boolean default false,
  created_at  timestamptz default now()
);

-- jobs (My Studio / Jobs Board)
create table if not exists jobs (
  id          bigint generated always as identity primary key,
  title       text,
  client_id   bigint references clients(id),
  invoice_id  bigint references invoices(id),
  status      text,
  assigned_to bigint references app_users(id),
  due_date    text,
  notes       text,
  items       jsonb,
  created_at  timestamptz default now()
);

-- inventory
create table if not exists inventory (
  id          bigint generated always as identity primary key,
  name        text,
  category    text,
  sku         text,
  quantity    numeric,
  unit        text,
  cost        numeric,
  reorder_at  numeric,
  notes       text,
  created_at  timestamptz default now()
);

-- app_settings (used by some modules)
create table if not exists app_settings (
  id         bigint generated always as identity primary key,
  key        text unique not null,
  value      jsonb,
  updated_at timestamptz default now()
);

-- ────────────────────────────────────────────────────────────
-- 2. RLS — Enable on all tables
-- ────────────────────────────────────────────────────────────

alter table settings       enable row level security;
alter table clients        enable row level security;
alter table invoices       enable row level security;
alter table estimates      enable row level security;
alter table transactions   enable row level security;
alter table expenses       enable row level security;
alter table pos_shifts     enable row level security;
alter table activity_log   enable row level security;
alter table app_users      enable row level security;
alter table messages       enable row level security;
alter table jobs           enable row level security;
alter table inventory      enable row level security;
alter table app_settings   enable row level security;

-- ────────────────────────────────────────────────────────────
-- 3. RLS POLICIES — authenticated users get full access
-- ────────────────────────────────────────────────────────────

-- Helper: run for each table to grant full access to authenticated users
-- (drop first in case they already exist from a previous run)

do $$ declare t text; begin
  foreach t in array array[
    'settings','clients','invoices','estimates','transactions',
    'expenses','pos_shifts','activity_log','app_users','messages',
    'jobs','inventory','app_settings'
  ] loop
    execute format('drop policy if exists "auth_all" on %I', t);
    execute format(
      'create policy "auth_all" on %I for all to authenticated using (true) with check (true)',
      t
    );
  end loop;
end $$;

-- ────────────────────────────────────────────────────────────
-- 4. PUBLIC READ — anonymous access for invoice share links
-- ────────────────────────────────────────────────────────────

-- Allow customers to view invoices via share link (no login)
drop policy if exists "public_read_invoices" on invoices;
create policy "public_read_invoices" on invoices
  for select to anon using (true);

-- Allow customers to view client info on invoice links
drop policy if exists "public_read_clients" on clients;
create policy "public_read_clients" on clients
  for select to anon using (true);

-- Allow payment method settings to show on public invoice pages
drop policy if exists "public_read_pay_settings" on settings;
create policy "public_read_pay_settings" on settings
  for select to anon using (key like 'pay_%');

-- Allow estimate approval links (no login needed)
drop policy if exists "public_read_estimates" on estimates;
create policy "public_read_estimates" on estimates
  for select to anon using (true);

drop policy if exists "public_update_estimates" on estimates;
create policy "public_update_estimates" on estimates
  for update to anon using (true) with check (true);

-- ────────────────────────────────────────────────────────────
-- 5. EXTRA COLUMNS — added after initial table creation
--    (safe to re-run — uses IF NOT EXISTS)
-- ────────────────────────────────────────────────────────────

alter table expenses   add column if not exists from_drawer boolean default false;
alter table expenses   add column if not exists shift_id    text;
alter table pos_shifts add column if not exists cashier_id  text;
alter table pos_shifts add column if not exists cashier_name text;

-- ────────────────────────────────────────────────────────────
-- 6. STORAGE BUCKET — for receipt / attachment uploads
-- ────────────────────────────────────────────────────────────

-- Run in Supabase Dashboard → Storage → New Bucket:
--   Name: message-attachments
--   Public: true
--
-- Or via SQL (requires pg_net / storage schema access):
-- insert into storage.buckets (id, name, public)
--   values ('message-attachments', 'message-attachments', true)
--   on conflict (id) do nothing;

-- ────────────────────────────────────────────────────────────
-- DONE. After running this script:
-- 1. Go to Settings → Business Info and save your business details
-- 2. Go to Settings → Payment Methods and re-enter your handles
-- 3. Open Point of Sale and open a new shift to verify pos_shifts works
-- ────────────────────────────────────────────────────────────
