-- ============================================================
--  WorldNotes — COMPLETE one-file setup
--  Paste this WHOLE file into: Supabase → SQL Editor → New query → Run
--
--  Creates everything the app needs on a fresh (free) Supabase
--  project: all tables, security policies, the photo storage
--  bucket, the full 243-country list, and starter settings.
--
--  Safe to re-run — everything is idempotent.
--  Equivalent to running the numbered files 1_ … 7_ in order.
--
--  AFTER RUNNING: create your account in the app, then run
--    update profiles set is_admin = true where email = 'YOUR_EMAIL';
--  to unlock the admin panel.
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
  id                   uuid primary key default gen_random_uuid(),
  country_id           int references countries(id),
  type                 text not null check (type in ('coin','banknote','accessory')),
  tab                  text not null check (tab in ('currency','coins','accessories')),
  category             text,                    -- UNC / Rare / Fantasy Notes / Shelves / …
  name                 text not null,
  description          text,
  price_cents          int  not null default 0, -- money stored as integer cents
  original_price_cents int,                     -- optional "was" price (struck through)
  quantity             int  not null default 0,
  is_rare              boolean not null default false,
  is_visible           boolean not null default true,
  tags                 text[] not null default '{}',  -- themes: animals, king, ibns, …
  created_at           timestamptz not null default now()
);
-- same columns for projects that ran an older base setup:
alter table products add column if not exists tags text[] not null default '{}';
alter table products add column if not exists original_price_cents int;
create index if not exists products_tags_gin on products using gin (tags);

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

-- Auto-create a profile whenever someone signs up (hardened version:
-- pinned search_path, duplicate-safe, and never blocks account creation).
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', ''))
  on conflict (id) do nothing;
  return new;
exception when others then
  return new;   -- the app repairs the profile row on first login if needed
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 4. ORDERS ----------

create sequence if not exists order_no_seq start 1;

create table if not exists orders (
  id              uuid primary key default gen_random_uuid(),
  order_no        int not null default nextval('order_no_seq'),
  user_id         uuid not null references profiles(id),
  subtotal_cents  int not null default 0,
  discount_cents  int not null default 0,
  shipping_cents  int not null default 0,
  total_cents     int not null default 0,
  coupon_code     text,
  status          text not null default 'processing'
                  check (status in ('processing','shipped','delivered')),
  created_at      timestamptz not null default now()
);
alter table orders add column if not exists shipping_cents int not null default 0;

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

create table if not exists events (            -- powers the trend dashboard
  id          uuid primary key default gen_random_uuid(),
  type        text not null check (type in ('search','view','wishlist','purchase')),
  product_id  uuid references products(id),
  search_term text,
  user_id     uuid references profiles(id),
  created_at  timestamptz not null default now()
);

create table if not exists store_settings (
  key   text primary key,
  value text
);

-- ============================================================
--  ROW-LEVEL SECURITY  (the safety layer for a static frontend)
-- ============================================================

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
drop policy if exists pub_read_continents on continents;
create policy pub_read_continents on continents for select using (true);
drop policy if exists adm_write_continents on continents;
create policy adm_write_continents on continents for all using (is_admin()) with check (is_admin());

drop policy if exists pub_read_countries on countries;
create policy pub_read_countries on countries for select using (true);
drop policy if exists adm_write_countries on countries;
create policy adm_write_countries on countries for all using (is_admin()) with check (is_admin());

drop policy if exists pub_read_products on products;
create policy pub_read_products on products for select using (is_visible or is_admin());
drop policy if exists adm_write_products on products;
create policy adm_write_products on products for all using (is_admin()) with check (is_admin());

drop policy if exists pub_read_images on product_images;
create policy pub_read_images on product_images for select using (true);
drop policy if exists adm_write_images on product_images;
create policy adm_write_images on product_images for all using (is_admin()) with check (is_admin());

drop policy if exists pub_read_coupons on coupons;
create policy pub_read_coupons on coupons for select using (is_active);
drop policy if exists adm_write_coupons on coupons;
create policy adm_write_coupons on coupons for all using (is_admin()) with check (is_admin());

drop policy if exists pub_read_settings on store_settings;
create policy pub_read_settings on store_settings for select using (true);
drop policy if exists adm_write_settings on store_settings;
create policy adm_write_settings on store_settings for all using (is_admin()) with check (is_admin());

-- Profile: each user sees/edits only their own; admins can read all;
-- users may also create their own row (signup fallback path)
drop policy if exists own_profile_read on profiles;
create policy own_profile_read on profiles for select using (id = auth.uid() or is_admin());
drop policy if exists own_profile_write on profiles;
create policy own_profile_write on profiles for update using (id = auth.uid()) with check (id = auth.uid());
drop policy if exists own_profile_insert on profiles;
create policy own_profile_insert on profiles for insert with check (id = auth.uid());

-- Cart / wishlist / notifications: strictly the owner
drop policy if exists own_cart on cart_items;
create policy own_cart on cart_items for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own_wish on wishlist_items;
create policy own_wish on wishlist_items for all using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists own_notif on stock_notifications;
create policy own_notif on stock_notifications for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- Orders: owner reads own + creates own; admins read all + update status
drop policy if exists own_orders_read on orders;
create policy own_orders_read on orders for select using (user_id = auth.uid() or is_admin());
drop policy if exists own_orders_insert on orders;
create policy own_orders_insert on orders for insert with check (user_id = auth.uid());
drop policy if exists adm_orders_update on orders;
create policy adm_orders_update on orders for update using (is_admin());
drop policy if exists order_items_read on order_items;
create policy order_items_read on order_items for select
  using (exists (select 1 from orders o where o.id = order_id and (o.user_id = auth.uid() or is_admin())));
drop policy if exists order_items_insert on order_items;
create policy order_items_insert on order_items for insert
  with check (exists (select 1 from orders o where o.id = order_id and o.user_id = auth.uid()));

-- Requests: user creates/reads own; admin sees & updates all
drop policy if exists req_own on product_requests;
create policy req_own on product_requests for select using (user_id = auth.uid() or is_admin());
drop policy if exists req_insert on product_requests;
create policy req_insert on product_requests for insert with check (user_id = auth.uid());
drop policy if exists req_admin on product_requests;
create policy req_admin on product_requests for update using (is_admin());

-- Events: anyone (even anon) can log; only admin reads them
drop policy if exists events_insert on events;
create policy events_insert on events for insert with check (true);
drop policy if exists events_read on events;
create policy events_read on events for select using (is_admin());

-- Inventory log: admin only
drop policy if exists inv_admin on inventory_log;
create policy inv_admin on inventory_log for all using (is_admin()) with check (is_admin());

-- ============================================================
--  PRODUCT PHOTO STORAGE (public bucket, admin-only writes)
-- ============================================================

insert into storage.buckets (id, name, public)
values ('product-photos', 'product-photos', true)
on conflict (id) do nothing;

drop policy if exists pub_read_product_photos   on storage.objects;
drop policy if exists adm_insert_product_photos on storage.objects;
drop policy if exists adm_update_product_photos on storage.objects;
drop policy if exists adm_delete_product_photos on storage.objects;

create policy pub_read_product_photos on storage.objects
  for select using (bucket_id = 'product-photos');
create policy adm_insert_product_photos on storage.objects
  for insert to authenticated
  with check (bucket_id = 'product-photos' and public.is_admin());
create policy adm_update_product_photos on storage.objects
  for update to authenticated
  using (bucket_id = 'product-photos' and public.is_admin());
create policy adm_delete_product_photos on storage.objects
  for delete to authenticated
  using (bucket_id = 'product-photos' and public.is_admin());

-- ============================================================
--  SEED DATA
-- ============================================================

insert into continents (name) values
  ('Africa'),('Asia'),('Europe'),('Americas'),('Oceania'),('Defunct / Unrecognized')
on conflict (name) do nothing;

-- Full country list: every current sovereign state, notable defunct
-- currency-issuing states, and unrecognized states.
create unique index if not exists countries_name_key on countries (name);

insert into countries (continent_id, name, iso_code, flag_emoji, status) values
-- ---------------- AFRICA (54) ----------------
((select id from continents where name='Africa'),'Algeria','DZ','🇩🇿','active'),
((select id from continents where name='Africa'),'Angola','AO','🇦🇴','active'),
((select id from continents where name='Africa'),'Benin','BJ','🇧🇯','active'),
((select id from continents where name='Africa'),'Botswana','BW','🇧🇼','active'),
((select id from continents where name='Africa'),'Burkina Faso','BF','🇧🇫','active'),
((select id from continents where name='Africa'),'Burundi','BI','🇧🇮','active'),
((select id from continents where name='Africa'),'Cabo Verde','CV','🇨🇻','active'),
((select id from continents where name='Africa'),'Cameroon','CM','🇨🇲','active'),
((select id from continents where name='Africa'),'Central African Republic','CF','🇨🇫','active'),
((select id from continents where name='Africa'),'Chad','TD','🇹🇩','active'),
((select id from continents where name='Africa'),'Comoros','KM','🇰🇲','active'),
((select id from continents where name='Africa'),'Republic of the Congo','CG','🇨🇬','active'),
((select id from continents where name='Africa'),'DR Congo','CD','🇨🇩','active'),
((select id from continents where name='Africa'),'Côte d''Ivoire','CI','🇨🇮','active'),
((select id from continents where name='Africa'),'Djibouti','DJ','🇩🇯','active'),
((select id from continents where name='Africa'),'Egypt','EG','🇪🇬','active'),
((select id from continents where name='Africa'),'Equatorial Guinea','GQ','🇬🇶','active'),
((select id from continents where name='Africa'),'Eritrea','ER','🇪🇷','active'),
((select id from continents where name='Africa'),'Eswatini','SZ','🇸🇿','active'),
((select id from continents where name='Africa'),'Ethiopia','ET','🇪🇹','active'),
((select id from continents where name='Africa'),'Gabon','GA','🇬🇦','active'),
((select id from continents where name='Africa'),'Gambia','GM','🇬🇲','active'),
((select id from continents where name='Africa'),'Ghana','GH','🇬🇭','active'),
((select id from continents where name='Africa'),'Guinea','GN','🇬🇳','active'),
((select id from continents where name='Africa'),'Guinea-Bissau','GW','🇬🇼','active'),
((select id from continents where name='Africa'),'Kenya','KE','🇰🇪','active'),
((select id from continents where name='Africa'),'Lesotho','LS','🇱🇸','active'),
((select id from continents where name='Africa'),'Liberia','LR','🇱🇷','active'),
((select id from continents where name='Africa'),'Libya','LY','🇱🇾','active'),
((select id from continents where name='Africa'),'Madagascar','MG','🇲🇬','active'),
((select id from continents where name='Africa'),'Malawi','MW','🇲🇼','active'),
((select id from continents where name='Africa'),'Mali','ML','🇲🇱','active'),
((select id from continents where name='Africa'),'Mauritania','MR','🇲🇷','active'),
((select id from continents where name='Africa'),'Mauritius','MU','🇲🇺','active'),
((select id from continents where name='Africa'),'Morocco','MA','🇲🇦','active'),
((select id from continents where name='Africa'),'Mozambique','MZ','🇲🇿','active'),
((select id from continents where name='Africa'),'Namibia','NA','🇳🇦','active'),
((select id from continents where name='Africa'),'Niger','NE','🇳🇪','active'),
((select id from continents where name='Africa'),'Nigeria','NG','🇳🇬','active'),
((select id from continents where name='Africa'),'Rwanda','RW','🇷🇼','active'),
((select id from continents where name='Africa'),'São Tomé and Príncipe','ST','🇸🇹','active'),
((select id from continents where name='Africa'),'Senegal','SN','🇸🇳','active'),
((select id from continents where name='Africa'),'Seychelles','SC','🇸🇨','active'),
((select id from continents where name='Africa'),'Sierra Leone','SL','🇸🇱','active'),
((select id from continents where name='Africa'),'Somalia','SO','🇸🇴','active'),
((select id from continents where name='Africa'),'South Africa','ZA','🇿🇦','active'),
((select id from continents where name='Africa'),'South Sudan','SS','🇸🇸','active'),
((select id from continents where name='Africa'),'Sudan','SD','🇸🇩','active'),
((select id from continents where name='Africa'),'Tanzania','TZ','🇹🇿','active'),
((select id from continents where name='Africa'),'Togo','TG','🇹🇬','active'),
((select id from continents where name='Africa'),'Tunisia','TN','🇹🇳','active'),
((select id from continents where name='Africa'),'Uganda','UG','🇺🇬','active'),
((select id from continents where name='Africa'),'Zambia','ZM','🇿🇲','active'),
((select id from continents where name='Africa'),'Zimbabwe','ZW','🇿🇼','active'),
-- ---------------- ASIA (48) ----------------
((select id from continents where name='Asia'),'Afghanistan','AF','🇦🇫','active'),
((select id from continents where name='Asia'),'Armenia','AM','🇦🇲','active'),
((select id from continents where name='Asia'),'Azerbaijan','AZ','🇦🇿','active'),
((select id from continents where name='Asia'),'Bahrain','BH','🇧🇭','active'),
((select id from continents where name='Asia'),'Bangladesh','BD','🇧🇩','active'),
((select id from continents where name='Asia'),'Bhutan','BT','🇧🇹','active'),
((select id from continents where name='Asia'),'Brunei','BN','🇧🇳','active'),
((select id from continents where name='Asia'),'Cambodia','KH','🇰🇭','active'),
((select id from continents where name='Asia'),'China','CN','🇨🇳','active'),
((select id from continents where name='Asia'),'Georgia','GE','🇬🇪','active'),
((select id from continents where name='Asia'),'India','IN','🇮🇳','active'),
((select id from continents where name='Asia'),'Indonesia','ID','🇮🇩','active'),
((select id from continents where name='Asia'),'Iran','IR','🇮🇷','active'),
((select id from continents where name='Asia'),'Iraq','IQ','🇮🇶','active'),
((select id from continents where name='Asia'),'Israel','IL','🇮🇱','active'),
((select id from continents where name='Asia'),'Japan','JP','🇯🇵','active'),
((select id from continents where name='Asia'),'Jordan','JO','🇯🇴','active'),
((select id from continents where name='Asia'),'Kazakhstan','KZ','🇰🇿','active'),
((select id from continents where name='Asia'),'Kuwait','KW','🇰🇼','active'),
((select id from continents where name='Asia'),'Kyrgyzstan','KG','🇰🇬','active'),
((select id from continents where name='Asia'),'Laos','LA','🇱🇦','active'),
((select id from continents where name='Asia'),'Lebanon','LB','🇱🇧','active'),
((select id from continents where name='Asia'),'Malaysia','MY','🇲🇾','active'),
((select id from continents where name='Asia'),'Maldives','MV','🇲🇻','active'),
((select id from continents where name='Asia'),'Mongolia','MN','🇲🇳','active'),
((select id from continents where name='Asia'),'Myanmar','MM','🇲🇲','active'),
((select id from continents where name='Asia'),'Nepal','NP','🇳🇵','active'),
((select id from continents where name='Asia'),'North Korea','KP','🇰🇵','active'),
((select id from continents where name='Asia'),'Oman','OM','🇴🇲','active'),
((select id from continents where name='Asia'),'Pakistan','PK','🇵🇰','active'),
((select id from continents where name='Asia'),'Palestine','PS','🇵🇸','active'),
((select id from continents where name='Asia'),'Philippines','PH','🇵🇭','active'),
((select id from continents where name='Asia'),'Qatar','QA','🇶🇦','active'),
((select id from continents where name='Asia'),'Saudi Arabia','SA','🇸🇦','active'),
((select id from continents where name='Asia'),'Singapore','SG','🇸🇬','active'),
((select id from continents where name='Asia'),'South Korea','KR','🇰🇷','active'),
((select id from continents where name='Asia'),'Sri Lanka','LK','🇱🇰','active'),
((select id from continents where name='Asia'),'Syria','SY','🇸🇾','active'),
((select id from continents where name='Asia'),'Taiwan','TW','🇹🇼','active'),
((select id from continents where name='Asia'),'Tajikistan','TJ','🇹🇯','active'),
((select id from continents where name='Asia'),'Thailand','TH','🇹🇭','active'),
((select id from continents where name='Asia'),'Timor-Leste','TL','🇹🇱','active'),
((select id from continents where name='Asia'),'Turkey','TR','🇹🇷','active'),
((select id from continents where name='Asia'),'Turkmenistan','TM','🇹🇲','active'),
((select id from continents where name='Asia'),'United Arab Emirates','AE','🇦🇪','active'),
((select id from continents where name='Asia'),'Uzbekistan','UZ','🇺🇿','active'),
((select id from continents where name='Asia'),'Vietnam','VN','🇻🇳','active'),
((select id from continents where name='Asia'),'Yemen','YE','🇾🇪','active'),
-- ---------------- EUROPE (46) ----------------
((select id from continents where name='Europe'),'Albania','AL','🇦🇱','active'),
((select id from continents where name='Europe'),'Andorra','AD','🇦🇩','active'),
((select id from continents where name='Europe'),'Austria','AT','🇦🇹','active'),
((select id from continents where name='Europe'),'Belarus','BY','🇧🇾','active'),
((select id from continents where name='Europe'),'Belgium','BE','🇧🇪','active'),
((select id from continents where name='Europe'),'Bosnia and Herzegovina','BA','🇧🇦','active'),
((select id from continents where name='Europe'),'Bulgaria','BG','🇧🇬','active'),
((select id from continents where name='Europe'),'Croatia','HR','🇭🇷','active'),
((select id from continents where name='Europe'),'Cyprus','CY','🇨🇾','active'),
((select id from continents where name='Europe'),'Czechia','CZ','🇨🇿','active'),
((select id from continents where name='Europe'),'Denmark','DK','🇩🇰','active'),
((select id from continents where name='Europe'),'Estonia','EE','🇪🇪','active'),
((select id from continents where name='Europe'),'Finland','FI','🇫🇮','active'),
((select id from continents where name='Europe'),'France','FR','🇫🇷','active'),
((select id from continents where name='Europe'),'Germany','DE','🇩🇪','active'),
((select id from continents where name='Europe'),'Greece','GR','🇬🇷','active'),
((select id from continents where name='Europe'),'Hungary','HU','🇭🇺','active'),
((select id from continents where name='Europe'),'Iceland','IS','🇮🇸','active'),
((select id from continents where name='Europe'),'Ireland','IE','🇮🇪','active'),
((select id from continents where name='Europe'),'Italy','IT','🇮🇹','active'),
((select id from continents where name='Europe'),'Kosovo','XK','🇽🇰','active'),
((select id from continents where name='Europe'),'Latvia','LV','🇱🇻','active'),
((select id from continents where name='Europe'),'Liechtenstein','LI','🇱🇮','active'),
((select id from continents where name='Europe'),'Lithuania','LT','🇱🇹','active'),
((select id from continents where name='Europe'),'Luxembourg','LU','🇱🇺','active'),
((select id from continents where name='Europe'),'Malta','MT','🇲🇹','active'),
((select id from continents where name='Europe'),'Moldova','MD','🇲🇩','active'),
((select id from continents where name='Europe'),'Monaco','MC','🇲🇨','active'),
((select id from continents where name='Europe'),'Montenegro','ME','🇲🇪','active'),
((select id from continents where name='Europe'),'Netherlands','NL','🇳🇱','active'),
((select id from continents where name='Europe'),'North Macedonia','MK','🇲🇰','active'),
((select id from continents where name='Europe'),'Norway','NO','🇳🇴','active'),
((select id from continents where name='Europe'),'Poland','PL','🇵🇱','active'),
((select id from continents where name='Europe'),'Portugal','PT','🇵🇹','active'),
((select id from continents where name='Europe'),'Romania','RO','🇷🇴','active'),
((select id from continents where name='Europe'),'Russia','RU','🇷🇺','active'),
((select id from continents where name='Europe'),'San Marino','SM','🇸🇲','active'),
((select id from continents where name='Europe'),'Serbia','RS','🇷🇸','active'),
((select id from continents where name='Europe'),'Slovakia','SK','🇸🇰','active'),
((select id from continents where name='Europe'),'Slovenia','SI','🇸🇮','active'),
((select id from continents where name='Europe'),'Spain','ES','🇪🇸','active'),
((select id from continents where name='Europe'),'Sweden','SE','🇸🇪','active'),
((select id from continents where name='Europe'),'Switzerland','CH','🇨🇭','active'),
((select id from continents where name='Europe'),'Ukraine','UA','🇺🇦','active'),
((select id from continents where name='Europe'),'United Kingdom','GB','🇬🇧','active'),
((select id from continents where name='Europe'),'Vatican City','VA','🇻🇦','active'),
-- ---------------- AMERICAS (35) ----------------
((select id from continents where name='Americas'),'Antigua and Barbuda','AG','🇦🇬','active'),
((select id from continents where name='Americas'),'Argentina','AR','🇦🇷','active'),
((select id from continents where name='Americas'),'Bahamas','BS','🇧🇸','active'),
((select id from continents where name='Americas'),'Barbados','BB','🇧🇧','active'),
((select id from continents where name='Americas'),'Belize','BZ','🇧🇿','active'),
((select id from continents where name='Americas'),'Bolivia','BO','🇧🇴','active'),
((select id from continents where name='Americas'),'Brazil','BR','🇧🇷','active'),
((select id from continents where name='Americas'),'Canada','CA','🇨🇦','active'),
((select id from continents where name='Americas'),'Chile','CL','🇨🇱','active'),
((select id from continents where name='Americas'),'Colombia','CO','🇨🇴','active'),
((select id from continents where name='Americas'),'Costa Rica','CR','🇨🇷','active'),
((select id from continents where name='Americas'),'Cuba','CU','🇨🇺','active'),
((select id from continents where name='Americas'),'Dominica','DM','🇩🇲','active'),
((select id from continents where name='Americas'),'Dominican Republic','DO','🇩🇴','active'),
((select id from continents where name='Americas'),'Ecuador','EC','🇪🇨','active'),
((select id from continents where name='Americas'),'El Salvador','SV','🇸🇻','active'),
((select id from continents where name='Americas'),'Grenada','GD','🇬🇩','active'),
((select id from continents where name='Americas'),'Guatemala','GT','🇬🇹','active'),
((select id from continents where name='Americas'),'Guyana','GY','🇬🇾','active'),
((select id from continents where name='Americas'),'Haiti','HT','🇭🇹','active'),
((select id from continents where name='Americas'),'Honduras','HN','🇭🇳','active'),
((select id from continents where name='Americas'),'Jamaica','JM','🇯🇲','active'),
((select id from continents where name='Americas'),'Mexico','MX','🇲🇽','active'),
((select id from continents where name='Americas'),'Nicaragua','NI','🇳🇮','active'),
((select id from continents where name='Americas'),'Panama','PA','🇵🇦','active'),
((select id from continents where name='Americas'),'Paraguay','PY','🇵🇾','active'),
((select id from continents where name='Americas'),'Peru','PE','🇵🇪','active'),
((select id from continents where name='Americas'),'Saint Kitts and Nevis','KN','🇰🇳','active'),
((select id from continents where name='Americas'),'Saint Lucia','LC','🇱🇨','active'),
((select id from continents where name='Americas'),'Saint Vincent and the Grenadines','VC','🇻🇨','active'),
((select id from continents where name='Americas'),'Suriname','SR','🇸🇷','active'),
((select id from continents where name='Americas'),'Trinidad and Tobago','TT','🇹🇹','active'),
((select id from continents where name='Americas'),'USA','US','🇺🇸','active'),
((select id from continents where name='Americas'),'Uruguay','UY','🇺🇾','active'),
((select id from continents where name='Americas'),'Venezuela','VE','🇻🇪','active'),
-- ---------------- OCEANIA (14) ----------------
((select id from continents where name='Oceania'),'Australia','AU','🇦🇺','active'),
((select id from continents where name='Oceania'),'Fiji','FJ','🇫🇯','active'),
((select id from continents where name='Oceania'),'Kiribati','KI','🇰🇮','active'),
((select id from continents where name='Oceania'),'Marshall Islands','MH','🇲🇭','active'),
((select id from continents where name='Oceania'),'Micronesia','FM','🇫🇲','active'),
((select id from continents where name='Oceania'),'Nauru','NR','🇳🇷','active'),
((select id from continents where name='Oceania'),'New Zealand','NZ','🇳🇿','active'),
((select id from continents where name='Oceania'),'Palau','PW','🇵🇼','active'),
((select id from continents where name='Oceania'),'Papua New Guinea','PG','🇵🇬','active'),
((select id from continents where name='Oceania'),'Samoa','WS','🇼🇸','active'),
((select id from continents where name='Oceania'),'Solomon Islands','SB','🇸🇧','active'),
((select id from continents where name='Oceania'),'Tonga','TO','🇹🇴','active'),
((select id from continents where name='Oceania'),'Tuvalu','TV','🇹🇻','active'),
((select id from continents where name='Oceania'),'Vanuatu','VU','🇻🇺','active'),
-- ---------------- DEFUNCT STATES (40) ----------------
((select id from continents where name='Defunct / Unrecognized'),'USSR',null,'☭','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Yugoslavia',null,'▨','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'East Germany',null,'▤','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Czechoslovakia',null,'▧','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Confederate States',null,'✦','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'West Germany',null,'🦅','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Weimar Republic',null,'🏛','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Russian Empire',null,'👑','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Austria-Hungary',null,'⚜','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Ottoman Empire',null,'☪','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Prussia',null,'✠','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Papal States',null,'🔑','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Free City of Danzig',null,'⚓','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Bohemia and Moravia',null,'🏰','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Serbia and Montenegro',null,'▩','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Rhodesia',null,'🦁','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Zaire',null,'🐆','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Biafra',null,'☀','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Katanga',null,'✚','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Zanzibar',null,'🌶','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Belgian Congo',null,'⭐','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'French West Africa',null,'🌍','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'German East Africa',null,'🏝','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'South Vietnam',null,'☰','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'French Indochina',null,'🐉','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Burma',null,'☸','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Siam',null,'🐘','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Ceylon',null,'🌴','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'British India',null,'♛','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Persia',null,'🦁','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Tibet',null,'🏔','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Manchukuo',null,'🌸','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Sikkim',null,'⛰','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'East Pakistan',null,'🌙','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'South Yemen',null,'★','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'North Yemen',null,'☽','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Straits Settlements',null,'⛵','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Netherlands Antilles',null,'🏖','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Kingdom of Hawaii',null,'🌺','defunct'),
((select id from continents where name='Defunct / Unrecognized'),'Republic of Texas',null,'✰','defunct'),
-- ---------------- UNRECOGNIZED / PARTIALLY RECOGNIZED (6) ----------------
((select id from continents where name='Defunct / Unrecognized'),'Somaliland',null,'🏴','unrecognized'),
((select id from continents where name='Defunct / Unrecognized'),'Transnistria',null,'🏴','unrecognized'),
((select id from continents where name='Defunct / Unrecognized'),'Abkhazia',null,'🏴','unrecognized'),
((select id from continents where name='Defunct / Unrecognized'),'South Ossetia',null,'🏴','unrecognized'),
((select id from continents where name='Defunct / Unrecognized'),'Northern Cyprus',null,'🏴','unrecognized'),
((select id from continents where name='Defunct / Unrecognized'),'Western Sahara','EH','🇪🇭','unrecognized')
on conflict (name) do update
  set continent_id = excluded.continent_id,
      iso_code     = excluded.iso_code,
      flag_emoji   = excluded.flag_emoji,
      status       = excluded.status;

-- Sample coupons (edit or delete in the admin panel)
insert into coupons (code, type, value, min_order_cents) values
  ('WORLD10','percent',10,0),
  ('FLAT5','flat',500,0),
  ('COLLECTOR','percent',15,5000)
on conflict (code) do nothing;

-- Store settings (all editable in admin → Settings)
insert into store_settings (key, value) values
  ('confirmation_message',
   'Thank you for collecting with WorldNotes! 🌍 Your order ships in 3–5 business days. Each note is inspected and sleeved before dispatch.'),
  ('shipping_charge_cents', '8000'),
  ('product_note',
   'Notes : The images listed are ONLY FOR REFERENCE. You will receive a different serial number.')
on conflict (key) do nothing;

-- ============================================================
--  DONE ✓
--  1. Open the app, click Login → Create account, and sign up.
--  2. Come back here and run (with your real email):
--       update profiles set is_admin = true where email = 'YOUR_EMAIL';
--  3. Reload the app — the Admin button appears. Enjoy!
-- ============================================================
