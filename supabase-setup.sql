-- ============================================================
--  WorldNotes — Supabase / PostgreSQL setup
--  Paste this whole file into: Supabase → SQL Editor → New query → Run
--  Safe to run on a fresh project. Creates tables, security, seeds.
-- ============================================================

-- ---------- 1. REFERENCE TABLES ----------

create table if not exists continents (
  id         serial primary key,
  name       text not null unique,
  is_active  boolean not null default true
);

create table if not exists countries (
  id            serial primary key,
  continent_id  int not null references continents(id),
  name          text not null,
  iso_code      text,
  flag_emoji    text,
  status        text not null default 'active'
                check (status in ('active','defunct','unrecognized')),
  is_enabled    boolean not null default true
);

-- ---------- 2. PRODUCTS ----------

create table if not exists products (
  id           uuid primary key default gen_random_uuid(),
  country_id   int references countries(id),
  type         text not null check (type in ('coin','banknote','accessory')),
  tab          text not null check (tab in ('currency','coins','accessories')),
  category     text,                          -- UNC / Rare / Polymer / Commemorative
  name         text not null,
  description  text,
  price_cents  int  not null default 0,       -- money stored as integer cents
  quantity     int  not null default 0,
  is_rare      boolean not null default false,
  is_visible   boolean not null default true,
  created_at   timestamptz not null default now()
);

create table if not exists product_images (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references products(id) on delete cascade,
  url         text not null,
  sort_order  int not null default 0
);

-- ---------- 3. USERS (profile extends Supabase Auth) ----------

create table if not exists profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  full_name  text,
  username   text unique,
  email      text,
  phone      text,
  address    text,
  is_admin   boolean not null default false,
  created_at timestamptz not null default now()
);

-- Auto-create a profile row whenever someone signs up
create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name',''));
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- 4. ORDERS ----------

create sequence if not exists order_no_seq start 1;   -- #6 numbers from 001

create table if not exists orders (
  id              uuid primary key default gen_random_uuid(),
  order_no        int not null default nextval('order_no_seq'),
  user_id         uuid not null references profiles(id),
  subtotal_cents  int not null default 0,
  discount_cents  int not null default 0,
  total_cents     int not null default 0,
  coupon_code     text,
  status          text not null default 'processing'
                  check (status in ('processing','shipped','delivered')),
  created_at      timestamptz not null default now()
);
-- Display helper: select format_order_no(order_no)  ->  'WC-001'
create or replace function format_order_no(n int)
returns text language sql immutable as $$ select 'WC-' || lpad(n::text, 3, '0') $$;

create table if not exists order_items (
  id                uuid primary key default gen_random_uuid(),
  order_id          uuid not null references orders(id) on delete cascade,
  product_id        uuid references products(id),
  qty               int not null,
  unit_price_cents  int not null            -- price captured at purchase time
);

-- ---------- 5. CART & WISHLIST ----------

create table if not exists cart_items (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  qty        int not null default 1,
  added_at   timestamptz not null default now(),
  unique (user_id, product_id)
);

create table if not exists wishlist_items (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references profiles(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  added_at   timestamptz not null default now(),
  unique (user_id, product_id)
);

-- ---------- 6. COUPONS ----------

create table if not exists coupons (
  id              uuid primary key default gen_random_uuid(),
  code            text not null unique,
  type            text not null check (type in ('percent','flat')),
  value           int  not null,             -- percent (10) or cents (500)
  min_order_cents int  not null default 0,
  is_active       boolean not null default true,
  expires_at      timestamptz
);

-- ---------- 7. INVENTORY / NOTIFICATIONS / REQUESTS / EVENTS ----------

create table if not exists inventory_log (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  change     int not null,
  reason     text not null check (reason in ('restock','sale','adjustment')),
  created_at timestamptz not null default now()
);

create table if not exists stock_notifications (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  user_id    uuid not null references profiles(id) on delete cascade,
  notified   boolean not null default false,
  unique (product_id, user_id)
);

create table if not exists product_requests (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references profiles(id),
  text       text not null,
  status     text not null default 'sourcing'
             check (status in ('sourcing','found','declined')),
  created_at timestamptz not null default now()
);

create table if not exists events (            -- powers the trend dashboard #13
  id          uuid primary key default gen_random_uuid(),
  type        text not null check (type in ('search','view','wishlist','purchase')),
  product_id  uuid references products(id),
  search_term text,
  user_id     uuid references profiles(id),
  created_at  timestamptz not null default now()
);

create table if not exists store_settings (    -- confirmation text #9, etc.
  key   text primary key,
  value text
);

-- ============================================================
--  ROW-LEVEL SECURITY  (the safety layer for a static frontend)
-- ============================================================

-- helper: is the current user an admin?
create or replace function is_admin()
returns boolean language sql stable security definer as $$
  select coalesce((select is_admin from profiles where id = auth.uid()), false)
$$;

alter table continents          enable row level security;
alter table countries           enable row level security;
alter table products            enable row level security;
alter table product_images      enable row level security;
alter table profiles            enable row level security;
alter table orders              enable row level security;
alter table order_items         enable row level security;
alter table cart_items          enable row level security;
alter table wishlist_items      enable row level security;
alter table coupons             enable row level security;
alter table inventory_log       enable row level security;
alter table stock_notifications enable row level security;
alter table product_requests    enable row level security;
alter table events              enable row level security;
alter table store_settings      enable row level security;

-- Public read of catalog; admin-only writes
create policy pub_read_continents on continents for select using (true);
create policy adm_write_continents on continents for all using (is_admin()) with check (is_admin());

create policy pub_read_countries on countries for select using (true);
create policy adm_write_countries on countries for all using (is_admin()) with check (is_admin());

create policy pub_read_products on products for select using (is_visible or is_admin());
create policy adm_write_products on products for all using (is_admin()) with check (is_admin());

create policy pub_read_images on product_images for select using (true);
create policy adm_write_images on product_images for all using (is_admin()) with check (is_admin());

create policy pub_read_coupons on coupons for select using (is_active);
create policy adm_write_coupons on coupons for all using (is_admin()) with check (is_admin());

create policy pub_read_settings on store_settings for select using (true);
create policy adm_write_settings on store_settings for all using (is_admin()) with check (is_admin());

-- Profile: each user sees/edits only their own; admins can read all
create policy own_profile_read on profiles for select using (id = auth.uid() or is_admin());
create policy own_profile_write on profiles for update using (id = auth.uid()) with check (id = auth.uid());

-- Cart / wishlist / notifications: strictly the owner
create policy own_cart on cart_items for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_wish on wishlist_items for all using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy own_notif on stock_notifications for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Orders: owner reads own + creates own; admins read all
create policy own_orders_read on orders for select using (user_id = auth.uid() or is_admin());
create policy own_orders_insert on orders for insert with check (user_id = auth.uid());
create policy adm_orders_update on orders for update using (is_admin());
create policy order_items_read on order_items for select
  using (exists (select 1 from orders o where o.id = order_id and (o.user_id = auth.uid() or is_admin())));
create policy order_items_insert on order_items for insert
  with check (exists (select 1 from orders o where o.id = order_id and o.user_id = auth.uid()));

-- Requests: user creates/reads own; admin sees & updates all
create policy req_own on product_requests for select using (user_id = auth.uid() or is_admin());
create policy req_insert on product_requests for insert with check (user_id = auth.uid());
create policy req_admin on product_requests for update using (is_admin());

-- Events: anyone (even anon) can log; only admin reads them for the dashboard
create policy events_insert on events for insert with check (true);
create policy events_read on events for select using (is_admin());

-- Inventory log: admin only
create policy inv_admin on inventory_log for all using (is_admin()) with check (is_admin());

-- ============================================================
--  SEED DATA
-- ============================================================

insert into continents (name) values
  ('Africa'),('Asia'),('Europe'),('Americas'),('Oceania'),('Defunct / Unrecognized')
on conflict (name) do nothing;

-- A starter set of countries (extend to the full ISO 3166 list later).
insert into countries (continent_id, name, iso_code, flag_emoji, status) values
  ((select id from continents where name='Africa'),'Zimbabwe','ZW','🇿🇼','active'),
  ((select id from continents where name='Africa'),'Egypt','EG','🇪🇬','active'),
  ((select id from continents where name='Africa'),'South Africa','ZA','🇿🇦','active'),
  ((select id from continents where name='Africa'),'Nigeria','NG','🇳🇬','active'),
  ((select id from continents where name='Asia'),'India','IN','🇮🇳','active'),
  ((select id from continents where name='Asia'),'Japan','JP','🇯🇵','active'),
  ((select id from continents where name='Asia'),'Singapore','SG','🇸🇬','active'),
  ((select id from continents where name='Asia'),'China','CN','🇨🇳','active'),
  ((select id from continents where name='Asia'),'Bhutan','BT','🇧🇹','active'),
  ((select id from continents where name='Europe'),'United Kingdom','GB','🇬🇧','active'),
  ((select id from continents where name='Europe'),'Germany','DE','🇩🇪','active'),
  ((select id from continents where name='Europe'),'Switzerland','CH','🇨🇭','active'),
  ((select id from continents where name='Europe'),'France','FR','🇫🇷','active'),
  ((select id from continents where name='Europe'),'Italy','IT','🇮🇹','active'),
  ((select id from continents where name='Americas'),'USA','US','🇺🇸','active'),
  ((select id from continents where name='Americas'),'Brazil','BR','🇧🇷','active'),
  ((select id from continents where name='Americas'),'Argentina','AR','🇦🇷','active'),
  ((select id from continents where name='Americas'),'Canada','CA','🇨🇦','active'),
  ((select id from continents where name='Oceania'),'Australia','AU','🇦🇺','active'),
  ((select id from continents where name='Oceania'),'New Zealand','NZ','🇳🇿','active'),
  ((select id from continents where name='Oceania'),'Fiji','FJ','🇫🇯','active'),
  ((select id from continents where name='Defunct / Unrecognized'),'USSR',null,'☭','defunct'),
  ((select id from continents where name='Defunct / Unrecognized'),'Yugoslavia',null,'▨','defunct'),
  ((select id from continents where name='Defunct / Unrecognized'),'East Germany',null,'▤','defunct'),
  ((select id from continents where name='Defunct / Unrecognized'),'Czechoslovakia',null,'▧','defunct'),
  ((select id from continents where name='Defunct / Unrecognized'),'Confederate States',null,'✦','defunct')
on conflict do nothing;

insert into coupons (code, type, value, min_order_cents) values
  ('WORLD10','percent',10,0),
  ('FLAT5','flat',500,0),
  ('COLLECTOR','percent',15,5000)
on conflict (code) do nothing;

insert into store_settings (key, value) values
  ('confirmation_message',
   'Thank you for collecting with WorldNotes! 🌍 Your order ships in 3–5 business days. Each note is inspected and sleeved before dispatch.')
on conflict (key) do nothing;

-- ============================================================
--  DONE.  Next: create your account in the app, then run:
--    update profiles set is_admin = true where email = 'YOUR_EMAIL';
--  to unlock the admin panel for yourself.
-- ============================================================
