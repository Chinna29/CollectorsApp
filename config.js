/* ============================================================
   WorldNotes — Supabase connection + shared helpers
   Loaded by index.html, admin.html, account.html
   (the @supabase/supabase-js CDN script must load BEFORE this file)
   ============================================================ */

const SUPABASE_URL = "https://nvliebngyufwrekmgzen.supabase.co";
const SUPABASE_KEY = "sb_publishable_BPkGW1U84E-qeCJ5N7dChw_yk1cBzxN";

const db = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);

/* ---------- money ---------- */
const money  = c => "$" + (c / 100).toFixed(2);       // cents -> "$12.50"
const toCents = v => Math.round(parseFloat(v || 0) * 100);

/* ---------- auth ---------- */
async function currentUser() {
  const { data } = await db.auth.getUser();
  return data.user || null;
}
async function myProfile() {
  const u = await currentUser();
  if (!u) return null;
  const { data } = await db.from("profiles").select("*").eq("id", u.id).single();
  return data;
}
async function signUp(email, password, extra = {}) {
  const { data, error } = await db.auth.signUp({ email, password });
  if (error) throw error;
  // Create/repair the profile row ourselves (works even if the DB trigger is off).
  // upsert = insert if missing, update if present. Requires a session, which
  // exists right after signup when "Confirm email" is turned off.
  if (data.user) {
    const { error: pErr } = await db
      .from("profiles")
      .upsert({ id: data.user.id, email, ...extra });
    if (pErr) console.warn("profile upsert:", pErr.message);
  }
  return data.user;
}
async function signIn(email, password) {
  const { data, error } = await db.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data.user;
}
async function signOut() { await db.auth.signOut(); }

/* ---------- catalog ---------- */
// products joined to their country (name + flag)
async function loadProducts(filter = {}) {
  let q = db.from("products").select("*, countries(name, flag_emoji, status)");
  if (filter.tab)      q = q.eq("tab", filter.tab);
  if (filter.category) q = q.eq("category", filter.category);
  if (filter.rare)     q = q.eq("is_rare", true);
  if (filter.outOfStock) q = q.eq("quantity", 0);
  if (filter.recent)   q = q.order("created_at", { ascending: false }).limit(12);
  const { data, error } = await q;
  if (error) { console.error(error); return []; }
  return data || [];
}
async function loadCountries() {
  const { data } = await db
    .from("countries")
    .select("id, name, flag_emoji, status, continent_id, continents(name)")
    .eq("is_enabled", true)
    .order("name");
  return data || [];
}

/* ---------- events (drives the dashboard) ---------- */
async function logEvent(type, { productId = null, term = null } = {}) {
  const u = await currentUser();
  await db.from("events").insert({
    type, product_id: productId, search_term: term, user_id: u ? u.id : null
  });
}

/* ---------- cart & wishlist ---------- */
async function addToCart(productId, qty = 1) {
  const u = await currentUser(); if (!u) throw new Error("login");
  // upsert on (user, product)
  const { data: existing } = await db.from("cart_items")
    .select("id, qty").eq("user_id", u.id).eq("product_id", productId).maybeSingle();
  if (existing) {
    await db.from("cart_items").update({ qty: existing.qty + qty }).eq("id", existing.id);
  } else {
    await db.from("cart_items").insert({ user_id: u.id, product_id: productId, qty });
  }
}
async function loadCart() {
  const u = await currentUser(); if (!u) return [];
  const { data } = await db.from("cart_items")
    .select("id, qty, product_id, products(name, price_cents, quantity, countries(flag_emoji))")
    .eq("user_id", u.id);
  return data || [];
}
async function setCartQty(id, qty) {
  if (qty <= 0) return db.from("cart_items").delete().eq("id", id);
  return db.from("cart_items").update({ qty }).eq("id", id);
}
async function toggleWishlist(productId) {
  const u = await currentUser(); if (!u) throw new Error("login");
  const { data: existing } = await db.from("wishlist_items")
    .select("id").eq("user_id", u.id).eq("product_id", productId).maybeSingle();
  if (existing) { await db.from("wishlist_items").delete().eq("id", existing.id); return false; }
  await db.from("wishlist_items").insert({ user_id: u.id, product_id: productId });
  return true;
}
async function loadWishlist() {
  const u = await currentUser(); if (!u) return [];
  const { data } = await db.from("wishlist_items")
    .select("id, product_id, products(name, price_cents, quantity, countries(flag_emoji))")
    .eq("user_id", u.id);
  return data || [];
}

/* ---------- coupons & orders ---------- */
async function findCoupon(code) {
  const { data } = await db.from("coupons")
    .select("*").eq("code", code.toUpperCase()).eq("is_active", true).maybeSingle();
  return data;
}
function discountCents(coupon, subtotalCents) {
  if (!coupon) return 0;
  if (coupon.min_order_cents && subtotalCents < coupon.min_order_cents) return 0;
  const d = coupon.type === "percent"
    ? Math.round(subtotalCents * coupon.value / 100)
    : coupon.value;
  return Math.min(d, subtotalCents);           // never exceed subtotal
}
async function placeOrder(cart, coupon) {
  const u = await currentUser(); if (!u) throw new Error("login");
  const subtotal = cart.reduce((s, i) => s + i.products.price_cents * i.qty, 0);
  const disc = discountCents(coupon, subtotal);
  const { data: order, error } = await db.from("orders").insert({
    user_id: u.id, subtotal_cents: subtotal, discount_cents: disc,
    total_cents: subtotal - disc, coupon_code: coupon ? coupon.code : null
  }).select("id, order_no").single();
  if (error) throw error;
  // order items + decrement stock + clear cart
  for (const i of cart) {
    await db.from("order_items").insert({
      order_id: order.id, product_id: i.product_id,
      qty: i.qty, unit_price_cents: i.products.price_cents
    });
    await db.from("products")
      .update({ quantity: Math.max(0, i.products.quantity - i.qty) })
      .eq("id", i.product_id);
    await logEvent("purchase", { productId: i.product_id });
  }
  await db.from("cart_items").delete().eq("user_id", u.id);
  return "WC-" + String(order.order_no).padStart(3, "0");
}

/* ---------- store settings ---------- */
async function getSetting(key) {
  const { data } = await db.from("store_settings").select("value").eq("key", key).maybeSingle();
  return data ? data.value : "";
}
async function setSetting(key, value) {
  await db.from("store_settings").upsert({ key, value });
}
