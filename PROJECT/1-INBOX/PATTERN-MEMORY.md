Great question! Let me analyze the codebase to identify the specific memory-hungry patterns causing the >512MB crashes.

Now let me check for the most dangerous pattern - loading full order objects:

Perfect! Now I can give you a detailed answer. Let me create a visual diagram showing the memory-hungry patterns:

Excellent question! Here are the **specific code patterns causing the >512MB memory crashes**:

---

## 🔴 **Pattern #1: WC_Order Object Bloat** (MOST DANGEROUS)

**Location**: `includes/class-kiss-woo-search.php`, line 777

````php path=includes/class-kiss-woo-search.php mode=EXCERPT
// Hydrate orders in one go.
$orders = wc_get_orders(
    array(
        'include' => $all_order_ids,
        'limit'   => -1,  // ⚠️ NO LIMIT!
        'orderby' => 'include',
    )
);
````

**Why This Crashes**:
- Each `WC_Order` object is **50-200KB** in memory
- Loads **ALL** order metadata (billing, shipping, payment, etc.)
- Loads **ALL** line items (products, quantities, prices)
- Loads **ALL** product data for each line item
- **Math**: 200 orders × 100KB = **20MB minimum**, often **50-100MB** with product data

---

## 🔴 **Pattern #2: Unbounded Candidate Limit** (MULTIPLIER EFFECT)

**Location**: `includes/class-kiss-woo-search.php`, line 725

````php path=includes/class-kiss-woo-search.php mode=EXCERPT
// Fetch more than the final per-customer cap because we apply the 10-per-customer cap in PHP.
// (Worst case: many recent orders belong to one customer.)
$candidate_limit = count( $user_ids ) * 10 * 5;  // ⚠️ DANGER!
````

**Why This Crashes**:
- **20 users** × 10 × 5 = **1,000 orders** fetched from SQL
- Then `wc_get_orders()` hydrates **ALL 1,000** into memory
- **Math**: 1,000 orders × 100KB = **100MB** just for orders
- **Worst case**: If users have many orders, this can fetch **5,000+ orders**

---

## 🔴 **Pattern #3: WP_User_Query Meta Cache** (ALREADY FIXED!)

**Location**: `includes/class-kiss-woo-search.php`, line 161 (NOW FIXED)

````php path=includes/class-kiss-woo-search.php mode=EXCERPT
$user_query = new WP_User_Query(
    array(
        'include'                => $user_ids,
        'fields'                 => $user_fields,  // ✅ GOOD: Only specific fields
        'update_user_meta_cache' => false,         // ✅ GOOD: Disabled meta cache
    )
);
````

**What Would Have Crashed** (if not fixed):
- Default `update_user_meta_cache => true` loads **ALL** usermeta
- Each user has **50-200 meta rows** (WooCommerce adds tons)
- **Math**: 1,000 users × 100 rows = **100,000 rows** in memory
- **Result**: **50-200MB** just for user metadata

**Good news**: Your code already has this fix! ✅


---

## 📊 **Real-World Crash Scenario**

Let's trace a typical crash:

1. **User searches for "john@example.com"**
2. **Customer lookup finds 20 users**
3. **Recent orders calculation**:
   - `candidate_limit = 20 × 10 × 5 = 1,000 orders`
   - SQL query fetches 1,000 order IDs
4. **wc_get_orders() hydrates 1,000 orders**:
   - 1,000 orders × 100KB = **100MB**
5. **Each order loads product data**:
   - 1,000 orders × 5 line items × 20KB per product = **100MB more**
6. **Total memory**: **200MB+ just for orders**
7. **Add user data, meta, etc.**: **50MB more**
8. **Total**: **250MB+**
9. **If multiple searches happen**: **500MB+**
10. **💥 CRASH!**

---

## ✅ **What We've Fixed So Far**

### Fixed in Existing Code:
- ✅ `update_user_meta_cache => false` (prevents meta bloat)
- ✅ `fields => ['ID', 'user_email', ...]` (only specific fields)
- ✅ Batch queries (prevents N+1)

### Fixed in Phase 2:
- ✅ Memory monitoring (50MB limit)
- ✅ Circuit breaker (throws exception before crash)
- ✅ Name splitting bug (prevents duplicate searches)

---

## 🚨 **What Still Needs Fixing**

### Critical (Phase 3):
1. **Cap `candidate_limit`** to absolute maximum (e.g., 200 orders max)
2. **Lazy-load order data** (fetch only IDs, load details on demand)
3. **Add result caching** (avoid re-fetching same data)

### Recommended:
4. **Use direct SQL for order summaries** (avoid WC_Order objects)
5. **Implement pagination** (don't load all results at once)
6. **Add query counting** (enforce <10 queries)

---

## 💡 **The Root Cause**

The fundamental issue is **WooCommerce's object model**:

- `WC_Order` objects are **HUGE** (50-200KB each)
- They eagerly load **ALL** related data
- No lazy loading by default
- No memory-aware limits

**Your code is actually pretty good** - it already avoids many WordPress/WooCommerce anti-patterns. The remaining issue is the **unbounded order hydration** in `get_recent_orders_for_customers()`.

---

## ✅ Scanner pattern status

These patterns from this doc now map to scanner rule IDs (usable for baselines/severity overrides):

- **Pattern #1 (WC_Order Object Bloat)** → `unbounded-wc-get-orders` (implemented; fixture: TODO)
- **Pattern #2 (Unbounded Candidate Limit / multiplier)** → `limit-multiplier-from-count` (implemented; heuristic; fixture: TODO)
- **Pattern #3 (WP_User_Query Meta Cache)** → `wp-user-query-meta-bloat` (implemented; fixture: TODO)

Related OOM patterns added alongside this work:

- `unbounded-wc-get-products` (implemented; fixture: TODO)
- `wp-query-unbounded` (implemented; fixture: TODO)
- `array-merge-in-loop` (implemented; heuristic; fixture: TODO)

## 🔎 Grep / ripgrep patterns to detect OOM risks

These are practical searches you can run to find **similar “unbounded hydration” patterns** elsewhere. Prefer `rg` (ripgrep) with PCRE2 because it supports better regex features.

### 1. WooCommerce: order/product hydration with no limit

- Find `wc_get_orders()` calls:
    - `rg -n "\bwc_get_orders\s*\(" -g'*.php'`
- Find explicit unlimited order loads:
    - `rg -n --pcre2 "wc_get_orders\s*\([^;]*\b(limit)\b\s*=>\s*-1" -g'*.php'`
- Find `wc_get_products()` unlimited loads (same object-bloat risk):
    - `rg -n --pcre2 "\bwc_get_products\s*\([^;]*\b(limit)\b\s*=>\s*-1" -g'*.php'`

STATUS: ✅ grep commands ready; ✅ scanner coverage (`unbounded-wc-get-orders`, `unbounded-wc-get-products`; fixtures TODO)

### 2. WordPress: unlimited queries (classic memory foot-gun)

- `WP_Query` unbounded:
    - `rg -n --pcre2 "new\s+WP_Query\s*\([^;]*posts_per_page\s*=>\s*-1" -g'*.php'`
    - `rg -n --pcre2 "new\s+WP_Query\s*\([^;]*nopaging\s*=>\s*true" -g'*.php'`
- `get_posts()` / `get_pages()` unbounded:
    - `rg -n --pcre2 "\bget_posts\s*\([^;]*(posts_per_page|numberposts)\s*=>\s*-1" -g'*.php'`

STATUS: ✅ grep commands ready; ✅ scanner coverage (`wp-query-unbounded`; fixtures TODO)

### 3.WordPress: user queries that may pull huge meta caches

- Find all `WP_User_Query` usage (manual review for meta caching + fields):
    - `rg -n "new\s+WP_User_Query\s*\(" -g'*.php'`
- Find `WP_User_Query` blocks missing `update_user_meta_cache` (multiline; best-effort):
    - `rg -n -U --pcre2 "new\s+WP_User_Query\s*\((?:(?!update_user_meta_cache).)*\);" -g'*.php'`
- Find `get_users()` calls (defaults can be heavy):
    - `rg -n "\bget_users\s*\(" -g'*.php'`
- Find places that explicitly request *all* fields (bigger objects):
    - `rg -n --pcre2 "\bfields\b\s*=>\s*('all'|\"all\")" -g'*.php'`

STATUS: ✅ grep commands ready; ✅ scanner coverage (`wp-user-query-meta-bloat`, `get-users-no-limit`; fixtures TODO)

### 4. Query “multiplier” patterns (limits derived from input size)

These don’t always indicate a bug, but they’re great at surfacing “count($x) * N” style blowups that can cascade into unbounded hydration.

- `count($something) * <number>`:
    - `rg -n --pcre2 "count\(\s*\$[a-zA-Z_][a-zA-Z0-9_]*\s*\)\s*\*\s*\d+" -g'*.php'`
- Look specifically for `candidate_limit`-style variables:
    - `rg -n --pcre2 "\bcandidate_?limit\b\s*=" -g'*.php'`

STATUS: ✅ grep commands ready; ✅ scanner coverage (`limit-multiplier-from-count`; heuristic; fixtures TODO)

### 5. “unbounded array growth” smells

Useful for finding “collect everything into an array” patterns that can explode memory.

- `array_merge` inside loops often balloons memory (review results):
    - `rg -n "\barray_merge\s*\(" -g'*.php'`
- Appending to arrays in loops (very broad; use when hunting):
    - `rg -n --pcre2 "\$[a-zA-Z_][a-zA-Z0-9_]*\s*\[\s*\]\s*=" -g'*.php'`

STATUS: ✅ grep commands ready; ✅ scanner coverage (`array-merge-in-loop`; heuristic; fixtures TODO)