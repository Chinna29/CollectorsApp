# CollectorsApp — WorldNotes

A website for selling a personal collection of **world currency** — banknotes, coins, and accessories from every country, including defunct nations (USSR, Yugoslavia, East Germany, and more). Each note carries its own story.

> **Status:** working mock / demo. Checkout records an order but takes **no real payment**.

## Tech stack
- **Frontend:** plain HTML / CSS / JavaScript (no framework, no build step) — hostable on GitHub Pages.
- **Backend:** [Supabase](https://supabase.com) — Postgres database, Auth, Storage, and Realtime.

## Pages
| File | Purpose |
|------|---------|
| `index.html` | Storefront — tabs (Currency / Coins / Accessories), filters, product grid, wishlist, cart, coupons, checkout, login/signup. |
| `account.html` | My Account — profile, order history, wishlist, product requests. |
| `admin.html` | Admin panel — dashboard, add product, inventory & restock, coupons, stock alerts, requests, confirmation message. |
| `config.js` | Supabase client + shared helper functions used by all pages. |

## Database
- `supabase-setup.sql` — full schema (15 tables), security rules, order-number sequence, and seed data.
- `fix-signup.sql` — hardened signup trigger.
- `database-schema.md` — human-readable schema documentation.

## Features
Account login/signup, browse by country/continent, UNC / Rare / Polymer filters, wishlist → cart, auto-incrementing order numbers (`WC-001`), coupons with accurate discount math, out-of-stock handling, an admin trend dashboard, product requests, and a customizable order-confirmation message.

## Running it
Open `index.html` in a browser. To manage products, create an account, then in Supabase run
`update profiles set is_admin = true where email = 'YOUR_EMAIL';` and reload — the Admin panel unlocks.

---
Built as a mock/demo project.
