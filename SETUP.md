# WorldNotes — Setup Guide

Get your own copy of this store running in about 20 minutes, completely free.

**What you need:** a [GitHub](https://github.com) account and a [Supabase](https://supabase.com) account (both free, sign up with any email).

**How it works:** the website itself is just files hosted on GitHub Pages (free static hosting). All the "moving parts" — customer accounts, products, orders, photos — live in your own Supabase project (free tier). The two talk to each other directly from the visitor's browser; there is no server for you to maintain.

---

## Part A — Create your Supabase backend

1. Go to [supabase.com](https://supabase.com) → **New project**
   - Name: anything (e.g. `my-currency-store`)
   - Database password: pick one and save it somewhere (you rarely need it again)
   - Region: closest to your customers
2. Wait ~2 minutes for the project to be created.
3. Open **SQL Editor** (left sidebar) → **New query**.
4. Open the file **`sqls/setup.sql`** from this repo, copy its ENTIRE contents, paste into the editor, and click **Run**.
   - You should see "Success". This creates all 15 tables, all security rules, the photo storage bucket, the full 243-country list, and starter settings — everything.
   - *Prefer smaller steps? The numbered files `sqls/1_...` through `sqls/7_...` do the same thing when run in order.*
5. Turn off email confirmation (so signups work instantly):
   - **Authentication → Sign In / Up → Email** → toggle **"Confirm email" OFF** → Save.
6. Collect your two connection values:
   - **Project Settings → Data API** → copy the **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **Project Settings → API Keys** → copy the **publishable / anon key** (a long string — this one is safe to be public; security is enforced by the database rules you just installed)

## Part B — Point the app at your project

1. Open **`config.js`** in this repo and replace the two values at the top:

   ```js
   const SUPABASE_URL = "https://YOUR-PROJECT.supabase.co";
   const SUPABASE_KEY = "YOUR-PUBLISHABLE-KEY";
   ```

2. Open **`.github/workflows/keepalive.yml`** and replace the URL and apikey there with the same two values. (This workflow pings your project twice a week so Supabase's free tier never pauses it for inactivity.)

## Part C — Host it on GitHub Pages

1. Create a new GitHub repository and upload all the files (or fork/copy this repo).
2. In the repo: **Settings → Pages → Source: "Deploy from a branch"** → Branch: `main`, folder: `/ (root)` → **Save**.
3. After ~1 minute your store is live at `https://YOUR-USERNAME.github.io/YOUR-REPO/`.

## Part D — Make yourself the admin

1. Open your live site → **Login → Create account** → sign up with your email.
2. Back in Supabase **SQL Editor**, run (with your real email):

   ```sql
   update profiles set is_admin = true where email = 'you@example.com';
   ```

3. Reload the site — a **🛠 Admin** button appears in the header. That's your control panel: add products with photos, manage inventory and coupons, view orders with customer details, print packing slips, and edit store settings.

## Part E — Make it yours

- **Admin → Settings:** shipping charge (default $80), the order-confirmation message, and the note shown on every product page.
- **Admin → Add product:** pick continent → country (all 243 available, including defunct states like the USSR), choose coin/banknote/accessory, set category, price (with optional struck-through "original" price), stock, theme tags, and upload photos — first photo becomes the cover.
- **Branding:** the shop name/logo lives near the top of `index.html`, `admin.html`, and `account.html` (search for "WorldNotes").

---

## Troubleshooting

| Problem | Fix |
|---|---|
| "Database error saving new user" on signup | You skipped part of `setup.sql` — re-run it (it's safe to re-run), and check "Confirm email" is OFF (Part A step 5). |
| Product publishes but photos fail ("bucket is missing") | The storage section of `setup.sql` didn't run — re-run the whole file. |
| Admin page says "not an admin yet" | Run the make-admin SQL from Part D with the exact email you signed up with, then reload. |
| Site loads but no products / spinner forever | Check `config.js` has YOUR project URL + key (Part B). Open the browser console (F12) — a 401 means the key is wrong. |
| Site worked, then died after a quiet week | Supabase paused the free project. Dashboard → Restore. Make sure the keep-alive workflow (Part B step 2) is set up — it prevents this. |
| Coupons don't apply | Coupon needs to be Active and the cart subtotal must meet its minimum. Manage them in Admin → Coupons. |

## FAQ

- **Does this cost anything?** No. GitHub Pages and the Supabase free tier (500MB database, 1GB photo storage — thousands of products) cover a small shop entirely.
- **Are payments processed?** No — checkout records the order with the customer's delivery details; you arrange payment & shipping directly with the buyer.
- **Is the key in `config.js` really safe to publish?** Yes. It's the *publishable* key; every read and write is checked against database-level security rules (customers only see their own data, only admins can write the catalog).
- **Can I use my own domain?** Yes — GitHub Pages supports custom domains (repo Settings → Pages → Custom domain).
