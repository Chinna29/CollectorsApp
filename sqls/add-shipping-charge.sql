-- ============================================================
-- WorldNotes — flat shipping charge
-- Run ONCE in the Supabase SQL editor. Safe to re-run.
--   * orders.shipping_cents — snapshot of the charge on each order
--   * store_settings.shipping_charge_cents — editable default ($80)
-- ============================================================

alter table orders add column if not exists shipping_cents int not null default 0;

insert into store_settings (key, value)
values ('shipping_charge_cents', '8000')
on conflict (key) do nothing;
