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
- `sqls/supabase-setup.sql` — full schema (already run on the project): 15 tables, RLS policies, order-number sequence, seed data.
- `sqls/fix-signup.sql` — hardened signup trigger (already run) that fixed a "Database error saving new user" issue.
- `sqls/storage-setup.sql` — creates the public `product-photos` Storage bucket + policies (public read, admin-only write). **Must be run once in the Supabase SQL editor** before photo upload works.
- `sqls/all-countries.sql` — full country seed (~243 rows: 197 active incl. Taiwan/Kosovo/Palestine, 40 defunct, 6 unrecognized). Upserts by name; safe to re-run. **Must be run once in the Supabase SQL editor** — until then only the 26 starter countries exist.
- `sqls/add-tags.sql` — adds `products.tags text[]` + GIN index for theme tags (animal, birds, queen, king, arms, ibns, …). **Must be run once in the Supabase SQL editor** — until then products publish fine but without tags (the frontend omits the column when the tags input is empty).
- `sqls/add-shipping-charge.sql` — adds `orders.shipping_cents` + `shipping_charge_cents` store setting (default $80, editable in admin Settings). **Must be run once in the Supabase SQL editor** — until then orders place without shipping (code falls back gracefully).
- `sqls/add-original-price.sql` — adds `products.original_price_cents` (optional struck-through "was" price) + seeds the `product_note` store setting shown on product detail views. **Must be run once in the Supabase SQL editor.**
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
1. **Product photo upload** — DONE in code (`uploadProductPhotos`/`firstImage` in `config.js`, upload box in admin Add-Product, images on storefront cards + drawer thumbs). Remaining manual step: run `sqls/storage-setup.sql` in the Supabase SQL editor to create the bucket, then test an admin upload in the browser.
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
