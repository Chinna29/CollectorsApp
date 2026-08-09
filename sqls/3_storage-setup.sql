-- ============================================================
-- WorldNotes — product photo storage (TODO #1)
-- Run this ONCE in the Supabase SQL editor (like supabase-setup.sql).
-- Creates the public `product-photos` bucket and its access policies:
--   * anyone can view photos (public bucket + read policy)
--   * only admins can upload / replace / delete them
-- Safe to re-run: policies are dropped and recreated.
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
