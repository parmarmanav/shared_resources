# Schema.sql — Deep Dive Explanation

This document explains every section of `schema.sql` in plain language. It focuses on **why** things are designed the way they are, how the functions work step-by-step, and what the unusual Postgres-specific patterns do.

---

## Table of Contents

1. [Extensions](#1-extensions)
2. [Table Architecture Overview](#2-table-architecture-overview)
3. [Module A — Members & Plans](#3-module-a--members--plans)
4. [Module B — Courts & Bookings](#4-module-b--courts--bookings)
5. [Module C — Shop & Bar](#5-module-c--shop--bar)
6. [Module D — Finance, Staff & Admin](#6-module-d--finance-staff--admin)
7. [Shared Helper Functions](#7-shared-helper-functions)
8. [Business Logic Functions (the hard stuff)](#8-business-logic-functions)
9. [Dashboard Views](#9-dashboard-views)
10. [Postgres-Specific Patterns Glossary](#10-postgres-specific-patterns-glossary)

---

## 1. Extensions

```sql
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "btree_gist";
```

| Extension | What it gives us | Why we need it |
|-----------|-----------------|----------------|
| `pgcrypto` | `gen_random_uuid()` function | Every table uses UUID primary keys instead of auto-increment integers. UUIDs are globally unique — no conflicts when merging data or in distributed systems. |
| `btree_gist` | GiST index support for common types | Originally planned for exclusion constraints on time ranges. Kept because it's harmless and useful if we add range-based constraints later. |

### Why UUIDs instead of integers?

```sql
id UUID PRIMARY KEY DEFAULT gen_random_uuid()
```

- **No sequential guessing**: A user can't guess `member/3` then `member/4`. UUIDs are random.
- **Safe for parallel inserts**: Two developers seeding data simultaneously won't collide.
- **Works across tables**: The `payments.reference_id` can point to a booking, order, or bar_order — all UUIDs, no type confusion.

---

## 2. Table Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                    MODULE A (Dev 1)                      │
│  plans ──→ members ←── leads                            │
└────────────┬────────────┬───────────────────────────────┘
             │            │
             │ (FK reads)  │ (FK reads)
             ▼            ▼
┌────────────────────┐  ┌──────────────────────────────────┐
│   MODULE B (Dev 2) │  │       MODULE C (Dev 3)           │
│ sports → courts    │  │ product_categories → products    │
│   → court_slots    │  │   → orders → order_items         │
│     → bookings     │  │ bar_menu_categories              │
│                    │  │   → bar_menu_items                │
│                    │  │ bar_tables → bar_orders           │
│                    │  │   → bar_order_items               │
└────────┬───────────┘  └──────────┬───────────────────────┘
         │                         │
         │  record_payment()       │  record_payment()
         ▼                         ▼
┌─────────────────────────────────────────────────────────┐
│                    MODULE D (Dev 4)                      │
│  staff, shifts, leave_requests, payroll                  │
│  payments (unified ledger) ← ALL money flows here       │
│  invoices → invoice_items                                │
└─────────────────────────────────────────────────────────┘
```

**Key design principle**: Money always ends up in ONE table (`payments`). The owner dashboard just queries that single table.

---

## 3. Module A — Members & Plans

### `plans` table — The "Rules Engine"

```sql
CREATE TABLE plans (
    court_rate        NUMERIC(10,2),     -- what a member pays per court session
    shop_discount_pct NUMERIC(5,2),      -- % off shop prices
    bar_discount_pct  NUMERIC(5,2),      -- % off bar prices
    daily_booking_limit INT DEFAULT 2,   -- max courts per day
    ...
);
```

**Why this matters**: Instead of writing code like `if (plan === 'Gold') { rate = 0; }`, all the rules are **data in the database**. Want to create a "Platinum" plan? Just INSERT a new row. No code changes needed.

The `CHECK` constraints ensure discount percentages stay between 0–100:

```sql
CHECK (shop_discount_pct >= 0 AND shop_discount_pct <= 100)
```

### `members` table

**Unusual things:**

- `email TEXT UNIQUE` — nullable but unique. Postgres allows multiple NULLs in a UNIQUE column (unlike MySQL). So members without email are fine.
- `plan_id UUID REFERENCES plans(id)` — nullable. A member might exist without a plan (e.g., during lead conversion).
- `client_type CHECK (client_type IN ('individual', 'business'))` — this is a **text-based enum** instead of a Postgres `ENUM` type. Why? Easier to add new values later without `ALTER TYPE`.

### `leads` table

```sql
assigned_staff_id UUID,  -- FK to staff added AFTER staff table
```

**Why the deferred FK?** The `staff` table is defined in Module D (line 304), but `leads` is in Module A (line 57). Since SQL runs top-to-bottom, we can't reference a table that doesn't exist yet. So we define the column here without the FK, then add it later with `ALTER TABLE` (line 322).

---

## 4. Module B — Courts & Bookings

### `court_slots` — The Time Grid

```sql
CONSTRAINT chk_slot_duration CHECK (end_time = start_time + INTERVAL '1 hour'),
CONSTRAINT uq_court_slot UNIQUE (court_id, start_time)
```

**What these do:**

1. **`chk_slot_duration`**: The database itself enforces that every slot is exactly 1 hour. You literally cannot insert a 45-minute or 2-hour slot — the DB will reject it.

2. **`uq_court_slot`**: No two slots can exist for the same court at the same start time. This prevents accidentally creating duplicate slots.

**The 30-minute overlap model:**

```
Court 1 slots on Monday:
  08:00 ─────────── 09:00    (Slot A)
       08:30 ─────────── 09:30    (Slot B)
            09:00 ─────────── 10:00    (Slot C)
                 09:30 ─────────── 10:30    (Slot D)
```

Each slot is a **separate row**. Slot A and Slot B overlap physically, but they are **independent bookable units**. The club decides operationally how to manage the overlap (e.g., player A finishes at 9:00, player B starts at 8:30 with a warm-up).

### `bookings` table

```sql
member_id    UUID REFERENCES members(id),  -- NULL for walk-ins
walker_name  TEXT,                          -- name for walk-in guests
walker_phone TEXT,                          -- phone for walk-in guests
price_charged NUMERIC(10,2) NOT NULL,       -- SNAPSHOT at booking time
```

**Why `member_id` is nullable**: Walk-ins don't have a member record. Instead, their name and phone go in `walker_name` / `walker_phone`.

**Why `price_charged` is a snapshot**: If the Gold plan rate changes from ₹0 to ₹100 tomorrow, today's bookings should still show ₹0. The price is **frozen** at the moment of booking.

### The Double-Booking Trigger — `trg_prevent_double_booking()`

This is the **database-level safety net**. Even if the application code has a bug, the database itself will never allow two people on the same non-social court.

```sql
CREATE OR REPLACE FUNCTION trg_prevent_double_booking()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
```

**What is a TRIGGER?**

A trigger is code that Postgres runs **automatically** before or after an INSERT/UPDATE/DELETE. You don't call it — it fires by itself.

```sql
CREATE TRIGGER trg_bookings_prevent_double
    BEFORE INSERT OR UPDATE ON bookings    -- fires BEFORE the row is written
    FOR EACH ROW                            -- runs once per row being inserted/updated
    EXECUTE FUNCTION trg_prevent_double_booking();
```

**Step-by-step walkthrough:**

```sql
-- Step 1: Is this booking even 'confirmed'? If not, let it through.
IF NEW.status != 'confirmed' THEN
    RETURN NEW;  -- RETURN NEW = allow the insert/update to proceed
END IF;
```

`NEW` is a special variable — it holds the row being inserted or updated.

```sql
-- Step 2: Is the slot social?
SELECT is_social INTO v_is_social FROM court_slots WHERE id = NEW.slot_id;
```

```sql
-- Step 3: If NOT social, check for existing confirmed bookings
IF NOT v_is_social THEN
    IF EXISTS (
        SELECT 1 FROM bookings
        WHERE slot_id = NEW.slot_id
          AND status = 'confirmed'
          AND id != COALESCE(NEW.id, '00000000-...'::UUID)
    ) THEN
        RAISE EXCEPTION 'SLOT_TAKEN' USING ERRCODE = 'P0001';
    END IF;
END IF;
```

**The `COALESCE` trick**: On INSERT, `NEW.id` might not be set yet (it gets its default UUID after the trigger). `COALESCE(NEW.id, '000...')` ensures we don't accidentally compare NULL != NULL (which is always NULL in SQL, not TRUE).

**`RAISE EXCEPTION`**: This aborts the INSERT entirely. The booking row is never created. The error message `'SLOT_TAKEN'` bubbles up to the Node.js backend as a catchable error.

---

## 5. Module C — Shop & Bar

### `products` table — Stock Management

```sql
stock_qty INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
```

**The `CHECK (stock_qty >= 0)` is critical.** This means the database will **never allow negative stock**. Even if there's a race condition in the app, the DB rejects the UPDATE. This is the last line of defense against overselling.

```sql
CREATE INDEX idx_products_stock ON products(stock_qty) WHERE is_active = TRUE;
```

**Partial index**: This index only covers active products. Inactive products are excluded, making the index smaller and faster. Used for the low-stock alert query.

### `orders` table — Unified for Online + In-Store

```sql
channel TEXT NOT NULL CHECK (channel IN ('in_store', 'online')),
fulfilment_type TEXT NOT NULL DEFAULT 'immediate' CHECK (fulfilment_type IN ('immediate', 'pickup', 'delivery')),
```

Both channels share the same table and the same stock. The `channel` field just records where the order came from. This is why online and in-store can't oversell — they're decrementing the same `stock_qty`.

### `order_items` — Price Snapshots

```sql
unit_price NUMERIC(10,2) NOT NULL,  -- price snapshot
```

Same principle as `bookings.price_charged` — the price is frozen at order time. If a racket goes from ₹18,999 to ₹19,999 tomorrow, yesterday's orders still show the old price.

```sql
REFERENCES orders(id) ON DELETE CASCADE
```

**`ON DELETE CASCADE`**: If you delete an order, all its line items are automatically deleted too. No orphaned order_items.

### Bar Tables and Tabs

```sql
-- bar_orders = "tabs"
status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'cancelled')),
```

A tab's lifecycle: **open** → items added → more items → ... → **closed** (payment recorded).

### `bar_order_items.kitchen_status`

```sql
kitchen_status TEXT NOT NULL DEFAULT 'ordered' 
    CHECK (kitchen_status IN ('ordered', 'preparing', 'ready', 'served')),
```

This drives the **Kitchen Display Screen**. When bar staff adds an item, it starts as `'ordered'`. Kitchen staff updates it to `'preparing'` → `'ready'`. Bar staff marks it `'served'` when delivered to the table.

---

## 6. Module D — Finance, Staff & Admin

### Deferred Foreign Keys via `ALTER TABLE`

```sql
ALTER TABLE leads ADD CONSTRAINT fk_leads_staff 
    FOREIGN KEY (assigned_staff_id) REFERENCES staff(id);
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_staff 
    FOREIGN KEY (booked_by_staff_id) REFERENCES staff(id);
ALTER TABLE orders ADD CONSTRAINT fk_orders_staff 
    FOREIGN KEY (placed_by_staff_id) REFERENCES staff(id);
ALTER TABLE bar_orders ADD CONSTRAINT fk_bar_orders_staff 
    FOREIGN KEY (served_by_staff_id) REFERENCES staff(id);
```

**Why ALTER TABLE instead of inline FK?** These tables (leads, bookings, orders, bar_orders) are defined BEFORE the `staff` table in the file. You can't reference a table that doesn't exist yet. So we create the columns first without FKs, then add the constraints after `staff` is created.

This is a common pattern when you have **circular or cross-module dependencies** in a single-file schema.

### `payments` — The Unified Ledger

```sql
CREATE TABLE payments (
    source       TEXT NOT NULL CHECK (source IN ('court', 'shop', 'bar', 'membership', 'invoice')),
    reference_id UUID NOT NULL,  -- points to the source record
    member_id    UUID REFERENCES members(id),
    amount       NUMERIC(10,2) NOT NULL,
    method       TEXT NOT NULL CHECK (method IN ('cash', 'card', 'upi')),
    ...
);
```

**This is the most important design decision in the entire schema.**

Every rupee that enters the club ends up as a row in this table. Whether it's a court booking, a racket purchase, a bar tab, or a membership payment — it's all here.

**Why `reference_id` is not a FK**: It points to different tables depending on `source`:

| `source` | `reference_id` points to |
|----------|-------------------------|
| `'court'` | `bookings.id` |
| `'shop'` | `orders.id` |
| `'bar'` | `bar_orders.id` |
| `'membership'` | `members.id` |
| `'invoice'` | `invoices.id` |

A single FK can't point to 5 different tables, so it's a UUID without a FK constraint. The `record_payment()` function ensures data integrity.

**Dashboard payoff**: The owner's "how much did we earn?" question becomes:

```sql
SELECT source, SUM(amount) FROM payments 
WHERE created_at >= '2026-10-01' GROUP BY source;
```

One query. Done.

### `payroll` — Unique Constraint

```sql
CONSTRAINT uq_payroll_staff_month UNIQUE (staff_id, month)
```

Each staff member can only have ONE payroll record per month. Running payroll generation twice for October won't create duplicates — the DB will reject the second insert.

---

## 7. Shared Helper Functions

### `get_entitlements(p_member_id UUID)`

**Called by**: Court bookings (to get court rate), Shop (to get discount), Bar (to get discount).

```sql
RETURNS TABLE (
    plan_name TEXT,
    court_rate NUMERIC,
    shop_discount_pct NUMERIC,
    bar_discount_pct NUMERIC,
    daily_booking_limit INT,
    is_active BOOLEAN
)
```

**`RETURNS TABLE`**: This function returns a **row**, not a single value. In Node.js:

```js
const { data } = await supabase.rpc('get_entitlements', { p_member_id: '...' });
// data = [{ plan_name: 'Gold', court_rate: 0, shop_discount_pct: 20, ... }]
```

**The `is_active` calculation**:

```sql
(m.status = 'active' AND m.membership_expiry >= CURRENT_DATE) AS is_active
```

This is a **computed boolean** — it checks both the status field AND whether the membership hasn't expired. A member could have `status = 'active'` but an expired date — this catches that.

### `record_payment(p_source, p_reference_id, p_amount, p_method, ...)`

**Called by**: Every function that takes money.

```sql
RETURNS UUID  -- returns the new payment ID
```

It validates `source` and `method` before inserting. This is the **single entry point** for writing to the `payments` table, ensuring every payment has valid data.

---

## 8. Business Logic Functions (The Hard Stuff)

### `book_court()` — The Most Complex Function

This is 90 lines of battle-tested booking logic. Let me walk through it:

#### Step 1: Row Lock

```sql
SELECT cs.*, c.walk_in_rate
INTO v_slot
FROM court_slots cs
JOIN courts c ON cs.court_id = c.id
WHERE cs.id = p_slot_id
FOR UPDATE;           -- ← THIS IS THE KEY
```

**`FOR UPDATE`** is a **row-level lock**. It means:

> "I'm reading this row AND I intend to modify something based on it. Nobody else can read it with FOR UPDATE until I'm done."

**Why is this critical?** Imagine two people booking the same slot at the same time:

```
Thread A: reads slot → sees it's free → ...
Thread B: reads slot → sees it's free → ...
Thread A: ... → inserts booking ✅
Thread B: ... → inserts booking ✅  ← DOUBLE BOOKING! 💥
```

With `FOR UPDATE`:

```
Thread A: locks slot → sees it's free → inserts booking → releases lock ✅
Thread B: waits... → lock released → reads slot → sees booking exists → SLOT_TAKEN ❌
```

#### Step 2: Future Check

```sql
IF v_slot.start_time <= NOW() THEN
    RAISE EXCEPTION 'SLOT_IN_PAST';
END IF;
```

Can't book a slot that already happened.

#### Step 3: Social Check

```sql
IF NOT v_slot.is_social THEN
    IF EXISTS (SELECT 1 FROM bookings WHERE slot_id = p_slot_id AND status = 'confirmed') THEN
        RAISE EXCEPTION 'SLOT_TAKEN';
    END IF;
END IF;
```

If the slot is social → skip this check → allow multiple bookings.
If the slot is NOT social → only one confirmed booking allowed.

#### Step 4: Timezone-Aware Daily Limit

```sql
v_slot_date := (v_slot.start_time AT TIME ZONE 'Asia/Kolkata')::DATE;
```

**Why this timezone conversion?** All timestamps are stored in UTC (`TIMESTAMPTZ`). But "today" for the club is in India time. A slot at `2026-10-03T23:30:00+05:30` is October 3 in India but `2026-10-03T18:00:00Z` in UTC. Without the conversion, the daily count could be wrong near midnight.

```sql
SELECT COUNT(*) INTO v_daily_count
FROM bookings b
JOIN court_slots cs2 ON b.slot_id = cs2.id
WHERE b.member_id = p_member_id
  AND b.status = 'confirmed'
  AND (cs2.start_time AT TIME ZONE 'Asia/Kolkata')::DATE = v_slot_date;

IF v_daily_count >= v_daily_limit THEN
    RAISE EXCEPTION 'DAILY_LIMIT_REACHED';
END IF;
```

Counts how many confirmed bookings this member has on the same India-time day. If they've hit their plan's limit (default 2), reject.

#### Step 5: Price Determination

```sql
IF p_member_id IS NOT NULL THEN
    -- Member: use plan's court_rate (could be 0 for Gold)
    v_price := v_court_rate;
ELSE
    -- Walk-in: use court's walk_in_rate (e.g., ₹500)
    v_price := v_slot.walk_in_rate;
END IF;
```

**Trial override**: If `p_is_trial = TRUE`, the price is set to the plan's `trial_rate` (seeded as ₹0).

### `cancel_booking()` — Simple but Important

```sql
UPDATE bookings
SET status = 'cancelled', cancelled_at = NOW()
WHERE id = p_booking_id AND status = 'confirmed';

IF NOT FOUND THEN
    RAISE EXCEPTION 'BOOKING_NOT_FOUND_OR_ALREADY_CANCELLED';
END IF;
```

**`NOT FOUND` after UPDATE**: In Postgres, `NOT FOUND` is true if the UPDATE matched zero rows. This means either the booking doesn't exist OR it's already cancelled. Either way, there's nothing to cancel.

**Important side effect**: Once a booking is `'cancelled'`, the trigger `trg_prevent_double_booking` will allow a new booking on that slot because it only checks `status = 'confirmed'`.

### `place_shop_order()` — Atomic Stock Decrement

#### The JSONB Items Pattern

```sql
p_items JSONB DEFAULT '[]'
```

The items list comes in as a JSON array from the API:

```json
[
  { "product_id": "abc-123", "quantity": 2 },
  { "product_id": "def-456", "quantity": 1 }
]
```

Then Postgres unpacks it:

```sql
FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, quantity INT)
LOOP
```

**`jsonb_to_recordset`** converts a JSONB array into virtual rows that you can loop over. This is how we pass a variable-length list of items into a SQL function.

#### The Atomic Stock Check

```sql
-- Lock the product row
SELECT * INTO v_product FROM products
WHERE id = v_item.product_id AND is_active = TRUE
FOR UPDATE;                    -- ← lock this product

-- Decrement stock atomically
UPDATE products
SET stock_qty = stock_qty - v_item.quantity
WHERE id = v_item.product_id
  AND stock_qty >= v_item.quantity;  -- ← THIS IS THE GUARD

IF NOT FOUND THEN
    RAISE EXCEPTION 'OUT_OF_STOCK';
END IF;
```

**Why `stock_qty >= v_item.quantity` in the WHERE clause?**

This is the **atomic check-and-decrement** pattern. The `UPDATE` only succeeds if there's enough stock. If two people try to buy the last racket simultaneously:

```
Stock = 1
Thread A: UPDATE ... SET stock_qty = 1 - 1 WHERE stock_qty >= 1  → matches → stock = 0 ✅
Thread B: UPDATE ... SET stock_qty = 0 - 1 WHERE stock_qty >= 1  → no match → NOT FOUND → OUT_OF_STOCK ❌
```

Plus the `CHECK (stock_qty >= 0)` constraint on the table is the final safety net — the DB will never let stock go negative.

### `open_bar_tab()` — Table Status Management

```sql
UPDATE bar_tables SET status = 'occupied' WHERE id = p_table_id;
```

**Why UPDATE instead of SELECT?** Two reasons:
1. It marks the table as occupied in the same operation.
2. `NOT FOUND` after UPDATE means the table doesn't exist — one query does both the check and the status change.

### `add_bar_item()` — Live Running Total

```sql
UPDATE bar_orders
SET subtotal = (SELECT COALESCE(SUM(line_total), 0) FROM bar_order_items WHERE bar_order_id = p_bar_order_id),
    discount_amount = ROUND(... * discount_pct / 100, 2),
    total = subtotal - discount_amount
WHERE id = p_bar_order_id;
```

Every time an item is added, the order's totals are recalculated from scratch by summing all items. This means the totals are always accurate, even if items are added by different staff members simultaneously.

**`COALESCE(SUM(...), 0)`**: If there are no items, `SUM()` returns NULL. `COALESCE` converts NULL → 0.

### `close_bar_tab()` — Table Release Logic

```sql
-- Free the table ONLY if no other open orders on it
IF NOT EXISTS (
    SELECT 1 FROM bar_orders
    WHERE table_id = v_order.table_id AND status = 'open' AND id != p_bar_order_id
) THEN
    UPDATE bar_tables SET status = 'available' WHERE id = v_order.table_id;
END IF;
```

**Why the EXISTS check?** A table might have multiple tabs open (e.g., two separate groups). We only free the table when the LAST tab is closed.

Then it calls `record_payment()` to write to the unified payments ledger:

```sql
SELECT record_payment('bar', p_bar_order_id, v_order.total, p_payment_method, ...)
INTO v_payment_id;
```

**This is function composition** — `close_bar_tab` calls `record_payment`, which inserts into `payments`. One call does everything.

### `register_member()` — Junior Age Check

```sql
IF v_plan.is_junior AND (p_date_of_birth IS NULL 
    OR AGE(CURRENT_DATE, p_date_of_birth) >= INTERVAL '18 years') THEN
    RAISE EXCEPTION 'JUNIOR_AGE_REQUIRED';
END IF;
```

**`AGE(date1, date2)`** returns an interval like `'13 years 2 months'`. The check ensures:
- If plan is Junior → DOB must be provided AND the person must be under 18.

**Dynamic expiry calculation:**

```sql
CURRENT_DATE + (v_plan.duration_months || ' months')::INTERVAL
```

`|| ' months'` concatenates the number with the string `' months'` to create `'12 months'`, then `::INTERVAL` casts it to a Postgres interval. So `CURRENT_DATE + INTERVAL '12 months'` = one year from now.

### `convert_lead()` — Function Composition

```sql
SELECT register_member(
    v_lead.full_name, v_lead.phone, v_lead.email,
    NULL, p_plan_id, 'individual', NULL, p_payment_method, p_staff_id
) INTO v_member_id;
```

This function **calls `register_member()` internally**. So converting a lead = creating a member + recording a payment, all in one transaction. If any step fails, everything rolls back.

```sql
SELECT * INTO v_lead FROM leads WHERE id = p_lead_id AND status != 'converted' FOR UPDATE;
```

The `FOR UPDATE` lock + `status != 'converted'` check prevents converting the same lead twice, even if two staff members click "Convert" simultaneously.

---

## 9. Dashboard Views

Views are **saved queries** — they look like tables but don't store data. They run the query every time you `SELECT` from them.

### `v_revenue_daily`

```sql
(created_at AT TIME ZONE 'Asia/Kolkata')::DATE AS day
```

Converts UTC timestamps to India time, then truncates to date. Groups by day + source + method, so you get rows like:

| day | source | method | txn_count | total_amount |
|-----|--------|--------|-----------|-------------|
| 2026-10-03 | court | card | 5 | 2500.00 |
| 2026-10-03 | bar | upi | 12 | 8400.00 |
| 2026-10-02 | shop | cash | 3 | 45997.00 |

### `v_member_status`

```sql
CASE
    WHEN m.status = 'suspended' THEN 'suspended'
    WHEN m.membership_expiry < CURRENT_DATE THEN 'expired'
    WHEN m.membership_expiry < CURRENT_DATE + INTERVAL '30 days' THEN 'expiring_soon'
    ELSE 'active'
END AS computed_status
```

**Why `computed_status` instead of trusting `members.status`?** A member might have `status = 'active'` in the DB, but their expiry date passed yesterday. This view catches that discrepancy and shows the real status.

### `v_low_stock`

```sql
WHERE p.is_active = TRUE AND p.stock_qty <= p.low_stock_threshold
```

Each product has its own `low_stock_threshold`. A cricket ball with threshold 5 and qty 2 shows up. A racket with threshold 3 and qty 8 doesn't.

### `v_today_bookings`

```sql
WHERE (cs.start_time AT TIME ZONE 'Asia/Kolkata')::DATE = (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE
```

Both sides are converted to India time before comparing. This ensures "today" means today in Kolkata, not today in UTC.

---

## 10. Postgres-Specific Patterns Glossary

### `RAISE EXCEPTION 'CODE' USING ERRCODE = 'P0001'`

Throws an error that aborts the current transaction. The error code `'P0001'` is a custom PL/pgSQL exception class. In Node.js, you catch it like:

```js
const { data, error } = await supabase.rpc('book_court', { ... });
if (error) {
    // error.message = 'SLOT_TAKEN'
    res.status(400).json({ error: error.message });
}
```

### `SELECT ... FOR UPDATE`

Locks the selected rows until the current transaction ends. Other transactions that try to `SELECT ... FOR UPDATE` on the same rows will **wait** (not fail). This serializes access to prevent race conditions.

### `RETURNS VOID`

The function doesn't return anything. Used for `cancel_booking()` — it either succeeds (no return needed) or throws an exception.

### `RETURNS TABLE (...)`

The function returns rows, like a mini-query. Each call returns 0 or more rows with the defined columns.

### `INTO v_variable`

Captures the result of a SELECT into a local variable:

```sql
SELECT price INTO v_price FROM bar_menu_items WHERE id = p_menu_item_id;
-- v_price now holds the price value
```

### `NOT FOUND`

A special boolean that's TRUE after a `SELECT INTO` or `UPDATE` that matched zero rows. It's the idiomatic way to check "did that query find anything?"

### `TIMESTAMPTZ` vs `TIMESTAMP`

- `TIMESTAMP` = naive datetime, no timezone info. "2026-10-03 18:00:00" — is that India time? UTC? Unknown.
- `TIMESTAMPTZ` = timezone-aware. Stored as UTC internally, displayed in session timezone. Always unambiguous.

We use `TIMESTAMPTZ` everywhere and convert with `AT TIME ZONE 'Asia/Kolkata'` when we need local Indian time.

### `NUMERIC(10,2)`

Fixed-precision decimal: 10 total digits, 2 after the decimal point. Max value: 99999999.99. **Never use FLOAT for money** — floating point has rounding errors (`0.1 + 0.2 = 0.30000000000000004`). NUMERIC is exact.

### `ON DELETE CASCADE`

When a parent row is deleted, all child rows are automatically deleted. Used on `order_items`, `bar_order_items`, and `invoice_items` so deleting an order cleans up its items.

### `COALESCE(value, fallback)`

Returns the first non-NULL argument. `COALESCE(NULL, 0)` = `0`. Used throughout to handle cases where a SUM or lookup might return NULL.

### Text-Based Enums via CHECK

```sql
status TEXT NOT NULL CHECK (status IN ('active', 'expired', 'suspended'))
```

**Why not Postgres ENUM type?** Adding a new value to a Postgres ENUM requires `ALTER TYPE ... ADD VALUE`, which can't run inside a transaction. Text + CHECK is more flexible — just update the CHECK constraint.
