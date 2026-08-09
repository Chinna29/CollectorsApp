-- ============================================================
--  FIX: "Database error saving new user"
--  Cause: the profile-creation trigger failed and blocked signup.
--  Paste this whole file into Supabase → SQL Editor → Run.
--  Safe to run on your existing project (it replaces, doesn't duplicate).
-- ============================================================

-- 1) Harden the signup trigger:
--    - set search_path (the usual cause of this error)
--    - do nothing if the row already exists
--    - never let a profile hiccup block account creation
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
  -- if anything goes wrong creating the profile, still let the user sign up;
  -- the app will create/repair the profile row on first login.
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2) Let a signed-in user create/repair their OWN profile row (fallback path).
--    (We already had read + update policies; this adds the missing insert.)
drop policy if exists own_profile_insert on profiles;
create policy own_profile_insert on profiles
  for insert with check (id = auth.uid());

-- Done. Try creating an account again.
