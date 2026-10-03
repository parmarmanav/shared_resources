# Sports Club Management System — Analysis & Module Split

## 1. Actors / Roles

| Actor | Description |
|-------|-------------|
| **Visitor** | Unauthenticated person browsing the public website |
| **Walk-in** | Non-member at the front desk (pays full price) |
| **Member (Gold)** | Premium tier — full access, best court rates, highest discounts |
| **Member (Silver)** | Standard tier — moderate discounts |
| **Member (Junior)** | Under-18, discounted rates, possible time/court restrictions |
| **Front Desk Staff** | Handles check-ins, bookings, POS for shop, manages walk-ins & calls |
| **Manager** | Oversees day-to-day operations, manages staff schedules, approves leave, views dashboard |
| **Bar Staff** | Takes orders, manages tabs, tracks tables, closes out at end of day |
| **Kitchen Staff** | Sees incoming bar/food orders, marks them ready |
| **Shop Staff** | Manages inventory, fulfils online orders for pickup/delivery |
| **Owner / Admin** | Full visibility — dashboard, invoices, payroll, reports, tax |

---

## 2. Scene-by-Scene Breakdown

### Scene A: A New Member Walks In

| Aspect | Detail |
|--------|--------|
| **Problem** | No structured member records; Excel sheets lose data |
| **Explicit rules** | 3 plan tiers: Gold, Silver, Junior (under-18). Plans define: court rates, shop discount %, bar discount %. Membership has an expiry date. |
| **Implied requirements** | Member profile (name, phone, email, DOB for Junior age check). Membership renewal workflow. Quick member lookup at front desk (search by name/phone). History view: bookings, purchases, bar tabs. Plan entitlements must be data-driven, not hardcoded. |

### Scene B: Booking a Court on a Busy Evening

| Aspect | Detail |
|--------|--------|
| **Problem** | WhatsApp/phone bookings → double-bookings, no visibility |
| **Explicit rules** | Sessions = 1 hour. New slot every 30 min (overlapping windows). Max 2 bookings per member per day. Members pay less than walk-ins (plan-driven). Some plans = free. Friday social play: many people share one court. Cancellation allowed. |
| **Implied requirements** | Court calendar with real-time availability. Database-level double-booking prevention (overlapping slot constraint). Walk-in booking (no member_id). Social-play mode flag on a slot (bypasses single-booker rule). Price snapshot at booking time. Cancellation frees the slot. Per-member daily limit enforced atomically. |

### Scene C: Gearing Up Before a Match (Shop)

| Aspect | Detail |
|--------|--------|
| **Problem** | No inventory system; stock unknown |
| **Explicit rules** | Categories: rackets, balls, shoes, accessories, apparel. Two channels: in-store (counter) and online (home). Online: pickup at club OR delivery. Same stock for both channels. |
| **Implied requirements** | Product catalog with category, price, stock_qty. Atomic stock decrement (prevent overselling). Low-stock alerts. Order with line items, channel (in_store / online), fulfilment_type (pickup / delivery / immediate). Member discount applied from plan. Price snapshot on order line. |

### Scene D: After the Match, at the Bar

| Aspect | Detail |
|--------|--------|
| **Problem** | Paper orders, lost tabs, no revenue tracking |
| **Explicit rules** | Members get discount (plan-driven). Tab system: order now, pay later (before leaving). Payment methods: cash, card, UPI. Staff work shifts. Tables tracked. Owner sees daily bar revenue. Kitchen needs to see orders. |
| **Implied requirements** | Bar menu (items, prices, categories). Table management (table number, status). Tab = open order tied to a table/member. Order items with kitchen status (ordered → preparing → ready → served). Shift management for bar staff. End-of-day reconciliation view. |

### Scene E: A Stranger Finds the Club Online (Website & Leads)

| Aspect | Detail |
|--------|--------|
| **Problem** | No web presence; lost leads |
| **Explicit rules** | Show: plans & prices, court availability this week, shop catalog. Visitor can book a trial session. Enquiry must not vanish — follow-up, send quote, convert to member. |
| **Implied requirements** | Public API endpoints (no auth) for plans, availability, products. Lead/enquiry table (name, contact, message, status). Lead assignment to staff. Trial booking type. Lead → member conversion flow. |

### Scene F: The Owner, End of Month

| Aspect | Detail |
|--------|--------|
| **Problem** | No unified financial view |
| **Explicit rules** | Revenue from: courts, shop, bar, memberships. Payment methods: card, cash, online/UPI. Invoices for memberships & business clients. Employee payroll, leave approval, tax reporting. Dashboard: today, this week, this month. Export/share capability. |
| **Implied requirements** | Unified payments table (source: court, shop, bar, membership). Invoice generation (line items, status: draft/sent/paid). Staff table with salary, leave balance. Leave requests (pending/approved/rejected). Payroll runs. Tax summary view. Dashboard views/aggregations. |

---

## 3. Contradictions & Ambiguities

| # | Issue | Assumption |
|---|-------|------------|
| 1 | PDF intro says "tennis, padel and badminton" but Scene 2 says "tennis and cricket courts" | **Store sports as configurable data in a `sports` table.** Seed with tennis and cricket per Scene 2. Adding padel/badminton is just an INSERT. |
| 2 | "Social play" — unclear if it's a separate booking type or a court mode | **Model as a `is_social` boolean on the booking slot.** Social slots allow multiple bookings on the same court-time. |
| 3 | Social play "Friday night" — is it only Fridays? | **Make social play available on any slot; the UI can default to Friday evenings.** The DB does not restrict by day. |
| 4 | Junior restrictions — PDF says "discounted" but doesn't specify time/court limits | **Junior gets a discount rate only.** No time-of-day restrictions unless added to the plans table later. |
| 5 | Bar "tab" — is it per-table, per-member, or per-visit? | **Tab = one open bar order per table. A member can be linked to a tab for discount.** |
| 6 | Delivery for online shop orders — does the club handle delivery? | **Model `fulfilment_type` as pickup/delivery. Delivery address stored on order.** Actual logistics are out of scope. |
| 7 | Trial session — free or paid? | **Configurable: add a `trial_rate` column to courts or plans.** Seed as free (0). |
| 8 | Tax reporting — which taxes? | **Store a tax summary view (total revenue by source, by month). Specific GST/tax rate config is out of scope for MVP.** |
| 9 | Payroll — how is salary structured? | **Simple monthly salary in staff table. Payroll = one record per staff per month.** No complex components. |
| 10 | "Business clients to invoice" — who are they? | **Any member or external entity. Add a `client_type` (individual/business) to members.** |

---

## 4. Four-Way Module Split

### Module A — Members & Plans (Developer 1)

**Owns:** members, plans, plan entitlements, membership lifecycle, public website data, leads/enquiries

**Tables:** `plans`, `members`, `leads`
**Key screens:** Member registration, member search/profile, plan management, leads list, public pages (plans, about)
**Shared dependency:** Provides `get_entitlements(member_id)` helper used by all other modules.

---

### Module B — Courts & Bookings (Developer 2)

**Owns:** Sports, courts, time slots, bookings, social play, availability calendar

**Tables:** `sports`, `courts`, `court_slots`, `bookings`
**Key screens:** Booking calendar, court management, availability view (public + staff), booking flow
**Shared dependency:** Calls `get_entitlements()` for pricing. Calls `record_payment()` for booking payments.

---

### Module C — Shop & Bar (Developer 3)

**Owns:** Product catalog, inventory, shop orders, bar menu, tables, tabs/bar orders, kitchen display

**Tables:** `product_categories`, `products`, `orders`, `order_items`, `bar_menu_categories`, `bar_menu_items`, `bar_tables`, `bar_orders`, `bar_order_items`
**Key screens:** POS (shop), online shop, bar order screen, kitchen display, table map
**Shared dependency:** Calls `get_entitlements()` for discounts. Calls `record_payment()` for payments.

---

### Module D — Finance, Staff & Admin (Developer 4)

**Owns:** Payments ledger, invoices, staff, shifts, leave, payroll, owner dashboard, reports

**Tables:** `payments`, `invoices`, `invoice_items`, `staff`, `shifts`, `leave_requests`, `payroll`
**Key screens:** Owner dashboard, invoice management, staff/shift management, leave approvals, payroll, reports
**Shared dependency:** Provides `record_payment()` helper used by all modules. Owns the `payments` table that everyone writes to.

---

### Shared Pieces (No Single Owner — Team Agreement)

| Shared Element | Used By | Governed By |
|----------------|---------|-------------|
| `payments` table | B, C, D | D owns the table; B and C write via `record_payment()` |
| `get_entitlements()` function | B, C | A owns the function |
| `record_payment()` function | A, B, C | D owns the function |
| `members` table (reads) | B, C, D | A owns; others read-only |
| `plans` table (reads) | B, C, D | A owns; others read-only |
| Auth middleware & role constants | All | Team-shared utility file |
| Error code enum | All | Defined in API.md, enforced in schema.sql |
