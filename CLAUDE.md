# WorldNotes — Project Context (for Claude Code)

This file gives you (Claude Code) the full context of this project. Read it first.

## What this is
A website for selling a personal collection of **world currency** (banknotes, coins, and accessories).
No real payment processing yet — checkout records an order but takes no money.
Frontend is plain **HTML/CSS/JavaScript** (no build step, no framework) so it can be hosted on **GitHub Pages**.
Backend is **Supabase** (Postgres + Auth + Storage + Realtime).

## Files in this folder
- `index.html` — storefront: tabs (Currency/Coins/Accessories), sub-filters, product grid, wishlist, cart, coupons, checkout, login/signup modal.
- `account.html` — My Account: profile, order history, wishlist, product requests.
- `admin.html` — Admin panel: dashboard (trends), add product, inventory/restock, coupons, stock alerts, requests, confirmation-message editor. Gated to `profiles.is_admin = true`.
- `config.js` — Supabase client + all shared helper functions (auth, catalog, cart, wishlist, coupons, orders, events, settings). All three pages load this.
- `SETUP.md` — buyer-facing setup guide: create Supabase project, run `sqls/setup.sql`, paste URL+key into `config.js`, enable GitHub Pages, make-admin SQL, troubleshooting.
- `sqls/setup.sql` — **one-file complete setup** for a fresh Supabase project (idempotent): all 15 tables (with tags/original_price/shipping columns baked in), hardened signup trigger, all RLS policies, `product-photos` storage bucket + policies, full 243-country seed, sample coupons, store settings. Equivalent to running the numbered files below in order.
- `sqls/1_supabase-setup.sql` … `sqls/7_add-original-price.sql` — the same setup as individual ordered steps (kept for manual/incremental setup on the existing project): 1 base schema+RLS+seeds, 2 hardened signup trigger, 3 storage bucket, 4 full country list, 5 product tags, 6 shipping charge, 7 original price + product note. On PV's own project, 1–2 are already run; 3–7 pending unless noted otherwise.
- `.github/workflows/keepalive.yml` — pings Supabase Mon+Thu so the free tier never pauses (must exist on `main` to run on schedule).
- `database-schema.md` — human-readable schema documentation.

## Supabase project
- URL: `https://nvliebngyufwrekmgzen.supabase.co`
- Publishable (anon) key is in `config.js` — safe for the frontend; RLS enforces all access rules.
- Auth: email + password. "Confirm email" should be OFF for easy testing.
- To grant admin: `update profiles set is_admin = true where email = 'THE_EMAIL';`

## Data model (short version)
`continents → countries → products → product_images`. Users have `profiles` (extends auth.users), plus `cart_items`, `wishlist_items`, `orders`/`order_items`, `product_requests`, `stock_notifications`. `coupons`, `events` (drives dashboard), and `store_settings` (confirmation text) are standalone. Money is stored as **integer cents** everywhere. Order numbers come from a Postgres sequence, displayed as `WC-001`.

## Current status — WORKING
Signup/login, admin add-product, storefront loads products from DB, cart/wishlist/orders persist, coupons apply with server-side-style math, dashboard reads real events. Tested manually in the browser.

## Known TODO (pick up here)
1. **Product photo upload** — DONE in code (`uploadProductPhotos`/`firstImage` in `config.js`, upload box in admin Add-Product, images on storefront cards + drawer thumbs). Remaining manual step: run `sqls/3_storage-setup.sql` in the Supabase SQL editor to create the bucket, then test an admin upload in the browser.
2. **Username & phone login** — currently email-only. Username login needs a `security definer` RPC to resolve username→email (RLS blocks reading other profiles). Phone login can use Supabase phone OTP.
3. **Out-of-stock notifications (#12)** — add a Supabase Edge Function (or trigger) that, when `products.quantity` hits 0, emails the admin and everyone with that product in cart/wishlist/`stock_notifications`.
4. **Recently-updated view** — add an `updated_at` column and a storefront view (#4).
5. **Polish** — loading states, error toasts, mobile spacing, empty states.
6. **Deploy to GitHub Pages** — init git, push to a repo, enable Pages on the `main` branch root. The site is fully static, so this just works once pushed.

## Conventions
- Keep it framework-free and single-file per page (works on GitHub Pages with no build).
- All DB access goes through helpers in `config.js` — add new helpers there, don't scatter `db.from(...)` calls across pages.
- Never trust the browser for pricing — recompute totals from DB values (see `discountCents` / `placeOrder`).
- Test each change in the browser against the live Supabase project before moving on.

## Suggested first move
Verify the app runs (`open index.html`), confirm you can log in and the admin panel loads, then start on TODO #1 (photo upload) — it's the most visible gap.
