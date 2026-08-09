# WorldNotes — Database Schema

This is the blueprint behind the mockups. It's written for **Supabase (PostgreSQL)**, which gives you authentication, database, photo storage, and real-time stock alerts on a free tier. Each table below maps to features from your original list (the `#` numbers).

---

## How the tables connect

```
continents ──< countries ──< products ──< product_images
                   │             │
                   │             ├──< inventory_log      (restock history #8)
                   │             ├──< cart_items >── users
                   │             └──< wishlist_items >── users
                   │
users ──< orders ──< order_items >── products
  │
  ├──< product_requests           (#14)
  └──< stock_notifications         (#12)

coupons        (standalone, checked at checkout #10, #11)
events         (search / view / buy / wishlist logs → dashboard #13)
store_settings (admin confirmation text #9, etc.)
```

A `country` belongs to a `continent`; a `product` belongs to a `country` and is either a coin or a banknote; everything a user does (cart, wishlist, orders, requests) links back to their `user` row.

---

## Tables

### 1. `continents`  *(seed once)*
| column | type | notes |
|---|---|---|
| id | int PK | |
| name | text | Africa, Asia, Europe, Americas, Oceania |
| is_active | bool | admin can hide a whole continent (#3) |

### 2. `countries`  *(seed from ISO 3166 + historical issuers — #3, #7)*
| column | type | notes |
|---|---|---|
| id | int PK | |
| continent_id | int FK → continents | |
| name | text | e.g. "Zimbabwe", "USSR" |
| iso_code | text null | null for defunct issuers |
| flag_emoji | text | |
| status | enum | `active` \| `defunct` \| `unrecognized` |
| is_enabled | bool | admin toggle so no country is missing but any can be disabled (#3) |

> **Seeding tip:** load all ~195 current countries from the ISO 3166 list, then append a curated list of defunct/unrecognized issuers (USSR, Yugoslavia, East Germany, Confederate States, Czechoslovakia, Katanga…). This guarantees "no country is missed."

### 3. `products`  *(#7)*
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| country_id | int FK → countries | |
| type | enum | `coin` \| `banknote` \| `accessory` |
| tab | enum | `currency` \| `coins` \| `accessories` |
| category | enum | `UNC` \| `Rare` \| `Polymer` \| `Commemorative` \| … |
| name | text | |
| description | text | the "story" shown on the card |
| price_cents | int | **store money as integers** to avoid rounding bugs (#11) |
| quantity | int | current stock |
| is_rare | bool | |
| is_visible | bool | admin show/hide |
| created_at | timestamptz | drives "Recently added" (#4) |

> **Out of stock** is simply `quantity = 0` — no separate flag needed. Your "Recently updated" and "Out of stock" views (#4) are just queries: `order by created_at desc` and `where quantity = 0`.

### 4. `product_images`  *(#7 — upload photos)*
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| product_id | uuid FK → products | |
| url | text | path in Supabase Storage bucket |
| sort_order | int | front, back, detail… |

### 5. `users`  *(#1, #15)*
Supabase Auth handles the login itself (email / phone / username + password). This table holds the **profile** that extends it.
| column | type | notes |
|---|---|---|
| id | uuid PK | = Supabase `auth.uid()` |
| full_name | text | |
| username | text unique | |
| email | text | |
| phone | text | |
| address | text | |
| is_admin | bool | gates the admin panel |

### 6. `orders`  *(#6)*
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| order_no | int | auto-increment from 1 via a Postgres `sequence` |
| user_id | uuid FK → users | |
| subtotal_cents | int | |
| discount_cents | int | from coupon |
| total_cents | int | |
| coupon_code | text null | |
| status | enum | `processing` \| `shipped` \| `delivered` |
| created_at | timestamptz | |

> **Order numbers (#6):** use a database `SEQUENCE` so numbers never collide, then format as `WC-001` in the app: `'WC-' || lpad(order_no::text, 3, '0')`.

### 7. `order_items`
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| order_id | uuid FK → orders | |
| product_id | uuid FK → products | |
| qty | int | |
| unit_price_cents | int | price **at time of purchase** (so later price changes don't rewrite history) |

### 8. `cart_items` & 9. `wishlist_items`  *(#5)*
Same shape — one row per (user, product):
| column | type |
|---|---|
| id | uuid PK |
| user_id | uuid FK → users |
| product_id | uuid FK → products |
| added_at | timestamptz |

> "Add to cart from wishlist" (#5) = insert into `cart_items`, optionally delete from `wishlist_items`.

### 10. `coupons`  *(#10, #11)*
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| code | text unique | |
| type | enum | `percent` \| `flat` |
| value | int | percent (e.g. 10) or cents (e.g. 500) |
| min_order_cents | int | 0 = no minimum |
| is_active | bool | admin toggle |
| expires_at | timestamptz null | |

> **Accurate coupon math (#11):** compute the discount **on the server**, in cents, never trusting the browser. `percent` → `round(subtotal * value / 100)`, capped at subtotal. This is the single most important rule for correct pricing.

### 11. `inventory_log`  *(#8 restock history)*
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| product_id | uuid FK → products | |
| change | int | +10 restock, −1 sale |
| reason | text | `restock` \| `sale` \| `adjustment` |
| created_at | timestamptz | |

### 12. `stock_notifications`  *(#12)*
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| product_id | uuid FK → products | |
| user_id | uuid FK → users | |
| notified | bool | flips true when restocked and user is emailed |

> **How #12 works:** when `quantity` drops to 0, a database trigger flags the product; a Supabase Edge Function then notifies the admin and every user with that product in cart/wishlist or on this notify list. Supabase **Realtime** can push a live "back in stock" update too.

### 13. `product_requests`  *(#14)*
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| user_id | uuid FK → users | |
| text | text | "Bhutan 100 Ngultrum, UNC" |
| status | enum | `sourcing` \| `found` \| `declined` |
| created_at | timestamptz | |

### 14. `events`  *(#13 trend dashboard)*
One tiny row per meaningful action — this is what powers the dashboard.
| column | type | notes |
|---|---|---|
| id | uuid PK | |
| type | enum | `search` \| `view` \| `wishlist` \| `purchase` |
| product_id | uuid null | null for free-text searches |
| search_term | text null | |
| user_id | uuid null | |
| created_at | timestamptz | |

> **Dashboard (#13)** = `select product_id, count(*) from events where type = 'search' group by product_id order by count desc`. The "searched but out of stock" insight is a join against `products.quantity = 0`.

### 15. `store_settings`  *(#9)*
| column | type | notes |
|---|---|---|
| key | text PK | e.g. `confirmation_message` |
| value | text | admin-editable confirmation text |

---

## Supabase specifics worth knowing

**Authentication (#1)** — Supabase Auth supports email, phone (OTP), and email+password out of the box. "Username login" is done by looking up the username in `users` and signing in with the linked email behind the scenes.

**Row-Level Security (RLS)** — this is the critical safety piece for a static-hosted frontend. Because anyone can read your frontend code, all "who can do what" rules live in the database:
- A user can read/write only **their own** cart, wishlist, orders, profile.
- **Anyone** can read visible products.
- Only rows where `is_admin = true` can insert products, restock, manage coupons, or edit settings.

This means even though the admin panel is just a web page, a non-admin literally cannot change inventory — the database refuses.

**Storage** — product photos (#7) go in a Supabase Storage bucket; `product_images.url` points to them.

**Realtime** — powers instant out-of-stock alerts (#12) without the user refreshing.

**Order numbers (#6)** — a `SEQUENCE` in Postgres, formatted `WC-001` in the app.

---

## Suggested build order (schema → live app)

1. Create the Supabase project (free).
2. Run the table creation SQL (I can generate the full SQL file next).
3. Seed `continents` and `countries` (ISO list + defunct issuers).
4. Turn on Auth + RLS policies.
5. Wire the mockups' buttons to real Supabase calls, one page at a time.

This is the point where moving to **Claude Code** makes sense — you'll be running the project locally, connecting to Supabase, and pushing to GitHub.
