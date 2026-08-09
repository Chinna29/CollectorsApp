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

/* ---------- product photos (Supabase Storage) ---------- */
const PHOTO_BUCKET = "product-photos";

// Upload photos for a product and record each in product_images.
// files: FileList/array from an <input type=file>. Returns public URLs.
// Requires the bucket from storage-setup.sql; admin-only per its policies.
async function uploadProductPhotos(productId, files) {
  const urls = [];
  let i = 0;
  for (const file of files) {
    const ext = (file.name.includes(".") ? file.name.split(".").pop() : "jpg").toLowerCase();
    const path = `${productId}/${Date.now()}-${i}.${ext}`;
    const { error } = await db.storage.from(PHOTO_BUCKET)
      .upload(path, file, { contentType: file.type || "image/jpeg" });
    if (error) throw error;
    const { data } = db.storage.from(PHOTO_BUCKET).getPublicUrl(path);
    const { error: imgErr } = await db.from("product_images")
      .insert({ product_id: productId, url: data.publicUrl, sort_order: i });
    if (imgErr) throw imgErr;
    urls.push(data.publicUrl);
    i++;
  }
  return urls;
}

// First (lowest sort_order) image URL of a row loaded with product_images(...), or null
function firstImage(p) {
  const imgs = p && p.product_images;
  if (!imgs || !imgs.length) return null;
  return imgs.slice().sort((a, b) => a.sort_order - b.sort_order)[0].url;
}

/* ---------- catalog ---------- */
// products joined to their country (name + flag) and photos
async function loadProducts(filter = {}) {
  let q = db.from("products").select("*, countries(name, flag_emoji, status), product_images(url, sort_order)");
  if (filter.tab)      q = q.eq("tab", filter.tab);
  if (filter.category) q = q.eq("category", filter.category);
  if (filter.rare)     q = q.eq("is_rare", true);
  if (filter.outOfStock) q = q.eq("quantity", 0);
  if (filter.recent)   q = q.order("created_at", { ascending: false }).limit(12);
  const { data, error } = await q;
  if (error) { console.error(error); return []; }
  return data || [];
}
// { all: true } returns every country regardless of is_enabled (admin panel)
async function loadCountries(opts = {}) {
  let q = db
    .from("countries")
    .select("id, name, flag_emoji, status, continent_id, continents(name)")
    .order("name");
  if (!opts.all) q = q.eq("is_enabled", true);
  const { data, error } = await q;
  if (error) { console.error(error); return []; }
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
    .select("id, qty, product_id, products(name, price_cents, quantity, countries(flag_emoji), product_images(url, sort_order))")
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
    .select("id, product_id, products(name, price_cents, quantity, countries(flag_emoji), product_images(url, sort_order))")
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
const DEFAULT_SHIPPING_CENTS = 8000;   // $80 flat — override via store_settings.shipping_charge_cents
async function getShippingCents() {
  const v = parseInt(await getSetting("shipping_charge_cents"), 10);
  return Number.isFinite(v) && v >= 0 ? v : DEFAULT_SHIPPING_CENTS;
}
async function placeOrder(cart, coupon) {
  const u = await currentUser(); if (!u) throw new Error("login");
  const subtotal = cart.reduce((s, i) => s + i.products.price_cents * i.qty, 0);
  const disc = discountCents(coupon, subtotal);
  const ship = await getShippingCents();
  const ins = {
    user_id: u.id, subtotal_cents: subtotal, discount_cents: disc,
    shipping_cents: ship, total_cents: subtotal - disc + ship,
    coupon_code: coupon ? coupon.code : null
  };
  let { data: order, error } = await db.from("orders").insert(ins).select("id, order_no").single();
  if (error && /shipping_cents/.test(error.message)) {
    // add-shipping-charge.sql not run yet — place the order without shipping
    delete ins.shipping_cents; ins.total_cents = subtotal - disc;
    ({ data: order, error } = await db.from("orders").insert(ins).select("id, order_no").single());
  }
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
