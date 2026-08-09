-- ============================================================
-- WorldNotes — product tags (themes: animal, birds, queen, king,
-- arms, ibns, …). Run ONCE in the Supabase SQL editor.
-- Safe to re-run.
-- ============================================================

alter table products add column if not exists tags text[] not null default '{}';

-- speeds up future tag filtering/search
create index if not exists products_tags_gin on products using gin (tags);
