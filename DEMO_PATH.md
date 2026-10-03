# Champions Club — Demo Script (~5 minutes)

> This script exercises every hard business rule from the PDF.
> Each step maps to the endpoint and SQL function involved.

---

## Pre-requisites
- `schema.sql` and `seed.sql` have been run on the Supabase instance.
- Backend is running at `http://localhost:3000`.
- Use `X-Dev-Role: owner` header for all authenticated calls during demo.

---

## Step 1: Public Website — Browse Plans & Availability (30 sec)

**What:** A stranger lands on the public website, sees plans and court availability.

| Action | Endpoint | SQL |
|--------|----------|-----|
| View membership plans | `GET /api/plans` | `SELECT * FROM plans` |
| Check court availability for today | `GET /api/slots/availability?date=today&sport_id=<tennis_id>` | `court_slots LEFT JOIN bookings` |
| Browse the shop catalog | `GET /api/products` | `SELECT * FROM products` |

**Show:** The 3 plans with prices, a calendar grid with open/booked slots, and the product list.

---

## Step 2: Website Lead Submission (30 sec)

**What:** The stranger submits an enquiry from the website.

| Action | Endpoint | SQL |
|--------|----------|-----|
| Submit enquiry | `POST /api/leads` `{ "full_name": "Demo Visitor", "phone": "9999000001", "email": "demo@test.com", "message": "Interested in Gold plan" }` | `INSERT INTO leads` |
| View lead in staff panel | `GET /api/leads` | `SELECT * FROM leads` |

**Show:** Lead appears in the leads list with status `new`.

---

## Step 3: Convert Lead → Register a New Gold Member (45 sec)

**What:** Front desk calls the lead back, converts them to a Gold member.

| Action | Endpoint | SQL |
|--------|----------|-----|
| Convert lead to member | `POST /api/leads/<lead_id>/convert` `{ "plan_id": "<gold_plan_id>", "payment_method": "card" }` | `convert_lead()` → `register_member()` → `record_payment('membership', ...)` |
| Verify member created | `GET /api/members?search=Demo` | `SELECT * FROM members` |
| Check entitlements | `GET /api/members/<id>/entitlements` | `get_entitlements()` |

**Show:** Member profile with Gold plan, court rate = ₹0, shop discount = 20%, bar discount = 15%. Payment of ₹15,000 recorded.

---

## Step 4: Book a Court — Success (30 sec)

**What:** The new Gold member books a tennis court for this evening.

| Action | Endpoint | SQL |
|--------|----------|-----|
| Find available evening slot | `GET /api/slots?court_id=<tennis_1>&date=today` | `court_slots LEFT JOIN bookings` |
| Book the slot | `POST /api/bookings` `{ "slot_id": "<6pm_slot_id>", "member_id": "<member_id>", "payment_method": "card" }` | `book_court()` → price = ₹0 (Gold) |

**Show:** Booking confirmed, price charged = ₹0. Slot now shows as booked.

---

## Step 5: Attempt Double Booking — BLOCKED (30 sec)

**What:** Another member tries to book the exact same slot.

| Action | Endpoint | SQL | Expected |
|--------|----------|-----|----------|
| Book same slot again | `POST /api/bookings` `{ "slot_id": "<same_6pm_slot>", "member_id": "<silver_member_id>" }` | `book_court()` | **Error: `SLOT_TAKEN`** |

**Show:** Error response `{ "error": "SLOT_TAKEN", "message": "This court slot is already booked" }`.

---

## Step 6: Hit Daily Booking Limit — BLOCKED (30 sec)

**What:** The Gold member already has 2 bookings today, tries a third.

| Action | Endpoint | SQL | Expected |
|--------|----------|-----|----------|
| Book a second slot (success) | `POST /api/bookings` `{ "slot_id": "<7pm_slot>", "member_id": "<member_id>" }` | `book_court()` | Success |
| Book a third slot (blocked) | `POST /api/bookings` `{ "slot_id": "<8pm_slot>", "member_id": "<member_id>" }` | `book_court()` | **Error: `DAILY_LIMIT_REACHED`** |

**Show:** Third booking rejected. The daily_booking_limit from the plans table (2) is enforced.

---

## Step 7: Cancel and Rebook (20 sec)

**What:** Member cancels one booking, freeing the slot for someone else.

| Action | Endpoint | SQL |
|--------|----------|-----|
| Cancel the 7pm booking | `POST /api/bookings/<id>/cancel` | `cancel_booking()` |
| Slot is now available again | `GET /api/slots?court_id=<tennis_1>&date=today` | Shows 7pm as available |

---

## Step 8: Shop Order — Online with Stock Drop (45 sec)

**What:** Member orders a racket from home (online), choosing pickup. Stock decrements atomically.

| Action | Endpoint | SQL |
|--------|----------|-----|
| Check product stock before | `GET /api/products/<pro_staff_97_id>` | `stock_qty = 8` |
| Place online order | `POST /api/orders` `{ "member_id": "<member_id>", "channel": "online", "fulfilment_type": "pickup", "items": [{ "product_id": "<pro_staff_97_id>", "quantity": 1 }], "payment_method": "upi" }` | `place_shop_order()` → atomic `UPDATE products SET stock_qty = stock_qty - 1 WHERE stock_qty >= 1` |
| Check stock after | `GET /api/products/<pro_staff_97_id>` | `stock_qty = 7` |
| Check low stock alerts | `GET /api/dashboard/low-stock` | `v_low_stock` shows Cricket Ball Red (qty=2) |

**Show:** Order total with 20% Gold discount applied. Stock dropped from 8 → 7. Low-stock view shows the cricket ball.

---

## Step 9: Shop — OUT_OF_STOCK (20 sec)

**What:** Try to buy 5 cricket balls when only 2 are in stock.

| Action | Endpoint | SQL | Expected |
|--------|----------|-----|----------|
| Order 5 cricket balls | `POST /api/orders` `{ "channel": "in_store", "items": [{ "product_id": "<cricket_ball_id>", "quantity": 5 }] }` | `place_shop_order()` | **Error: `OUT_OF_STOCK`** |

**Show:** Atomic stock check prevents overselling.

---

## Step 10: Bar — Open Tab, Order, Kitchen Display (60 sec)

**What:** 20 people arrive. Open a tab at Table 3, add food/drinks, see orders in kitchen.

| Action | Endpoint | SQL |
|--------|----------|-----|
| Open tab at Table 3 for Gold member | `POST /api/bar/orders` `{ "table_id": "<table_3_id>", "member_id": "<member_id>" }` | `open_bar_tab()` → discount_pct = 15% |
| Add 4x Fresh Lime Soda | `POST /api/bar/orders/<id>/items` `{ "menu_item_id": "<lime_soda_id>", "quantity": 4 }` | `add_bar_item()` |
| Add 2x Paneer Tikka | `POST /api/bar/orders/<id>/items` `{ "menu_item_id": "<paneer_tikka_id>", "quantity": 2 }` | `add_bar_item()` |
| Add 1x Butter Chicken | `POST /api/bar/orders/<id>/items` `{ "menu_item_id": "<butter_chicken_id>", "quantity": 1 }` | `add_bar_item()` |
| Kitchen sees new orders | `GET /api/bar/kitchen` | `SELECT * FROM bar_order_items WHERE kitchen_status != 'served'` |
| Kitchen marks Paneer Tikka as preparing | `PATCH /api/bar/kitchen/<item_id>` `{ "kitchen_status": "preparing" }` | `UPDATE bar_order_items` |
| Kitchen marks it ready | `PATCH /api/bar/kitchen/<item_id>` `{ "kitchen_status": "ready" }` | `UPDATE bar_order_items` |

**Show:** Tab running total updates with each item. Kitchen display shows items with statuses. Table 3 shows as `occupied`.

---

## Step 11: Settle the Bar Tab with Member Discount (30 sec)

**What:** Member is leaving. Close the tab and pay.

| Action | Endpoint | SQL |
|--------|----------|-----|
| View the tab total | `GET /api/bar/orders/<id>` | Shows subtotal, 15% discount, final total |
| Close and pay by UPI | `POST /api/bar/orders/<id>/close` `{ "payment_method": "upi" }` | `close_bar_tab()` → `record_payment('bar', ...)` |

**Show:** Subtotal = ₹1,543. Discount (15%) = ₹231.45. Total = ₹1,311.55. Table 3 back to `available`. Payment recorded.

**Calculation:** 4 × ₹99 (lime) + 2 × ₹349 (paneer) + 1 × ₹449 (butter chicken) = ₹396 + ₹698 + ₹449 = ₹1,543.

---

## Step 12: Owner Dashboard — End of Month (30 sec)

**What:** The owner opens the dashboard and sees unified financials.

| Action | Endpoint | SQL |
|--------|----------|-----|
| Dashboard summary | `GET /api/dashboard/summary` | Multiple views |
| Revenue this month by source | `GET /api/dashboard/revenue?period=month` | `v_revenue_daily`, `v_revenue_by_source` |
| Revenue breakdown by payment method | Same response | Grouped by `method` |
| Member status overview | `GET /api/dashboard/members` | `v_member_status` |
| Low stock alerts | `GET /api/dashboard/low-stock` | `v_low_stock` |

**Show:** 
- Total revenue card (all sources combined)
- Bar chart: revenue by source (courts / shop / bar / membership)
- Pie chart: payment methods (cash / card / UPI)
- Member status: active, expiring soon (Amit Kumar), expired (Deepa Rao)
- Low stock alert: Cricket Ball Red (2 left, threshold 5)

---

## Summary: Business Rules Exercised

| Business Rule | Step | Enforced By |
|---------------|------|-------------|
| 3 plan tiers with different entitlements | 1, 3 | `plans` table (data, not code) |
| Member registration with age check | 3 | `register_member()` |
| Court booking with price snapshot | 4 | `book_court()` |
| Double-booking prevention | 5 | `book_court()` — row lock + EXISTS check |
| Daily booking limit (max 2) | 6 | `book_court()` — count + plan limit |
| Cancellation frees slot | 7 | `cancel_booking()` |
| Same stock for online/in-store | 8 | `products.stock_qty` — single source |
| Atomic stock decrement | 8, 9 | `UPDATE ... WHERE stock_qty >= qty` |
| Member discount at shop | 8 | `place_shop_order()` — reads plan |
| Member discount at bar | 10, 11 | `open_bar_tab()` — reads plan |
| Tab system (order now, pay later) | 10, 11 | `bar_orders` status open → closed |
| Kitchen display with status tracking | 10 | `bar_order_items.kitchen_status` |
| Multiple payment methods | 4, 8, 11 | `payments.method` CHECK constraint |
| Website leads → conversion | 2, 3 | `leads` table + `convert_lead()` |
| Unified revenue dashboard | 12 | `payments` table + dashboard views |
| Low stock alerts | 8 | `v_low_stock` view |
| Member expiry tracking | 12 | `v_member_status` view |
