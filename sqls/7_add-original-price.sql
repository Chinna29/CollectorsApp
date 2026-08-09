-- ============================================================
-- WorldNotes — product detail page extras
-- Run ONCE in the Supabase SQL editor. Safe to re-run.
--   * products.original_price_cents — optional "was" price, shown
--     struck through next to the selling price
--   * store_settings.product_note — italic note shown on every
--     product detail view (editable in admin Settings)
-- ============================================================

alter table products add column if not exists original_price_cents int;

insert into store_settings (key, value)
values ('product_note', 'Notes : The images listed are ONLY FOR REFERENCE. You will receive a different serial number.')
on conflict (key) do nothing;
