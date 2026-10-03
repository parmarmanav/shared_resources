# Champions Club — API Contract

> **Any change to a table, column, or endpoint MUST update this file in the same commit.**

---

## Conventions

### Base URL
```
http://localhost:3000/api
```

### Auth Header
```
Authorization: Bearer <jwt_token>
```

### Dev-Auth Shortcut (early development only)
During development, pass a staff role directly:
```
X-Dev-Role: owner | admin | manager | front_desk | bar_staff | kitchen_staff | shop_staff
X-Dev-Staff-Id: <staff_uuid>
```
The auth middleware checks `X-Dev-Role` first; if present, it skips JWT verification and injects the role and staff ID into `req.user`. **Remove before production.**

### Time Format
All timestamps: ISO 8601 with timezone → `2026-10-03T18:30:00+05:30`  
All dates: `YYYY-MM-DD`  
All times: `HH:MM`  

### Money Format
All monetary values are `number` with 2 decimal places in INR (₹).  
Example: `15000.00`

### Error Response Shape
```json
{
  "error": "SLOT_TAKEN",
  "message": "This court slot is already booked"
}
```

### Error Codes (complete list)
| Code | Source |
|------|--------|
| `SLOT_NOT_FOUND` | book_court |
| `SLOT_IN_PAST` | book_court |
| `SLOT_TAKEN` | book_court |
| `MEMBER_NOT_ACTIVE` | book_court |
| `DAILY_LIMIT_REACHED` | book_court |
| `BOOKING_NOT_FOUND_OR_ALREADY_CANCELLED` | cancel_booking |
| `MEMBER_NOT_FOUND` | get_entitlements |
| `PLAN_NOT_FOUND` | register_member |
| `JUNIOR_AGE_REQUIRED` | register_member |
| `PRODUCT_NOT_FOUND` | place_shop_order |
| `OUT_OF_STOCK` | place_shop_order |
| `TABLE_NOT_FOUND` | open_bar_tab |
| `BAR_ORDER_NOT_FOUND` | close_bar_tab, add_bar_item |
| `BAR_ORDER_CLOSED` | close_bar_tab, add_bar_item |
| `MENU_ITEM_NOT_AVAILABLE` | add_bar_item |
| `LEAD_NOT_FOUND_OR_ALREADY_CONVERTED` | convert_lead |
| `INVALID_PAYMENT_SOURCE` | record_payment |
| `INVALID_PAYMENT_METHOD` | record_payment |

### Roles
| Role | Description |
|------|-------------|
| `owner` | Full access to everything including payroll, invoices, tax |
| `admin` | Full access to everything including payroll, invoices, tax |
| `manager` | Manages staff, shifts, leave, members, bookings, leads, dashboard — no payroll/invoices |
| `front_desk` | Members, bookings, shop POS, leads |
| `bar_staff` | Bar orders, tabs, tables |
| `kitchen_staff` | Kitchen display (bar order items) |
| `shop_staff` | Products, inventory, shop orders |
| `public` | Unauthenticated — website endpoints only |

---

## Module A — Members & Plans (Developer 1)

### Plans

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/plans` | public | — | `Plan[]` | `SELECT * FROM plans` | — |
| GET | `/plans/:id` | public | — | `Plan` | `SELECT * FROM plans WHERE id=` | — |
| POST | `/plans` | admin, owner | `{ name, description, court_rate, shop_discount_pct, bar_discount_pct, daily_booking_limit, duration_months, price, is_junior, trial_rate }` | `Plan` | `INSERT INTO plans` | — |
| PATCH | `/plans/:id` | admin, owner | partial `Plan` fields | `Plan` | `UPDATE plans` | — |

### Members

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/members` | front_desk, manager, admin, owner | query: `?search=&status=&plan=` | `Member[]` | `SELECT * FROM members` with filters | — |
| GET | `/members/:id` | front_desk, manager, admin, owner | — | `Member` with plan details | `JOIN plans` | — |
| GET | `/members/:id/entitlements` | front_desk, manager, admin, owner | — | `Entitlements` | `get_entitlements(id)` | `MEMBER_NOT_FOUND` |
| GET | `/members/:id/history` | front_desk, manager, admin, owner | — | `{ bookings, orders, bar_orders, payments }` | Multi-table query | — |
| POST | `/members` | front_desk, manager, admin, owner | `{ full_name, phone, email?, date_of_birth?, plan_id?, client_type?, address?, payment_method? }` | `{ member_id }` | `register_member()` | `PLAN_NOT_FOUND`, `JUNIOR_AGE_REQUIRED` |
| PATCH | `/members/:id` | front_desk, manager, admin, owner | partial fields | `Member` | `UPDATE members` | — |
| POST | `/members/:id/renew` | front_desk, manager, admin, owner | `{ plan_id, payment_method }` | `{ member_id }` | Update expiry + `record_payment()` | — |

### Leads / Enquiries

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/leads` | front_desk, manager, admin, owner | query: `?status=` | `Lead[]` | `SELECT * FROM leads` | — |
| GET | `/leads/:id` | front_desk, manager, admin, owner | — | `Lead` | `SELECT * FROM leads WHERE id=` | — |
| POST | `/leads` | public, front_desk, manager | `{ full_name, phone, email?, message?, source? }` | `{ lead_id }` | `INSERT INTO leads` | — |
| PATCH | `/leads/:id` | front_desk, manager, admin, owner | `{ status?, assigned_staff_id?, notes? }` | `Lead` | `UPDATE leads` | — |
| POST | `/leads/:id/convert` | front_desk, manager, admin, owner | `{ plan_id, payment_method? }` | `{ member_id }` | `convert_lead()` | `LEAD_NOT_FOUND_OR_ALREADY_CONVERTED`, `PLAN_NOT_FOUND` |

---

## Module B — Courts & Bookings (Developer 2)

### Sports & Courts

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/sports` | public | — | `Sport[]` | `SELECT * FROM sports` | — |
| GET | `/courts` | public | query: `?sport_id=` | `Court[]` | `SELECT * FROM courts` | — |
| POST | `/courts` | admin, owner | `{ name, sport_id, walk_in_rate }` | `Court` | `INSERT INTO courts` | — |
| PATCH | `/courts/:id` | admin, owner | partial fields | `Court` | `UPDATE courts` | — |

### Slots & Availability

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/slots` | public | query: `?court_id=&date=&sport_id=` | `Slot[]` with `is_booked` flag | `court_slots LEFT JOIN bookings` | — |
| GET | `/slots/availability` | public | query: `?date=&sport_id=` | `{ court_id, court_name, slots: [{ start, end, is_available, is_social }] }[]` | Aggregated query | — |
| POST | `/slots` | admin, owner | `{ court_id, start_time, end_time, is_social }` | `Slot` | `INSERT INTO court_slots` | — |
| PATCH | `/slots/:id` | admin, owner | `{ is_social }` | `Slot` | `UPDATE court_slots` | — |

### Bookings

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/bookings` | front_desk, manager, admin, owner | query: `?date=&court_id=&member_id=&status=` | `Booking[]` | `v_today_bookings` or filtered | — |
| GET | `/bookings/:id` | front_desk, manager, admin, owner | — | `Booking` with slot + member details | JOIN query | — |
| POST | `/bookings` | front_desk, manager, admin, owner | `{ slot_id, member_id?, walker_name?, walker_phone?, is_trial?, payment_method? }` | `{ booking_id, price_charged }` | `book_court()` then `record_payment('court', ...)` | `SLOT_NOT_FOUND`, `SLOT_IN_PAST`, `SLOT_TAKEN`, `MEMBER_NOT_ACTIVE`, `DAILY_LIMIT_REACHED` |
| POST | `/bookings/:id/cancel` | front_desk, manager, admin, owner | — | `{ success: true }` | `cancel_booking()` | `BOOKING_NOT_FOUND_OR_ALREADY_CANCELLED` |

---

## Module C — Shop & Bar (Developer 3)

### Product Categories & Products

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/product-categories` | public | — | `Category[]` | `SELECT * FROM product_categories` | — |
| GET | `/products` | public | query: `?category_id=&search=&in_stock=` | `Product[]` | `SELECT * FROM products` | — |
| GET | `/products/:id` | public | — | `Product` | `SELECT * FROM products WHERE id=` | — |
| POST | `/products` | shop_staff, admin, owner | `{ category_id, name, description?, price, stock_qty, low_stock_threshold?, image_url? }` | `Product` | `INSERT INTO products` | — |
| PATCH | `/products/:id` | shop_staff, admin, owner | partial fields | `Product` | `UPDATE products` | — |
| PATCH | `/products/:id/stock` | shop_staff, admin, owner | `{ adjustment }` (positive=add, negative=remove) | `Product` | `UPDATE products SET stock_qty = stock_qty + adj` | — |

### Shop Orders

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/orders` | front_desk, shop_staff, manager, admin, owner | query: `?status=&channel=&member_id=` | `Order[]` | `SELECT * FROM orders` | — |
| GET | `/orders/:id` | front_desk, shop_staff, manager, admin, owner | — | `Order` with items | JOIN order_items | — |
| POST | `/orders` | front_desk, shop_staff, public | `{ member_id?, channel, fulfilment_type?, delivery_address?, items: [{ product_id, quantity }], payment_method? }` | `{ order_id, total }` | `place_shop_order()` then `record_payment('shop', ...)` | `PRODUCT_NOT_FOUND`, `OUT_OF_STOCK` |
| PATCH | `/orders/:id/status` | shop_staff, manager, admin, owner | `{ status }` | `Order` | `UPDATE orders` | — |

### Bar Menu

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/bar/menu-categories` | bar_staff, admin, owner | — | `Category[]` | `SELECT * FROM bar_menu_categories` | — |
| GET | `/bar/menu` | bar_staff, admin, owner | query: `?category_id=&available=` | `MenuItem[]` | `SELECT * FROM bar_menu_items` | — |
| POST | `/bar/menu` | admin, owner | `{ category_id, name, description?, price }` | `MenuItem` | `INSERT INTO bar_menu_items` | — |
| PATCH | `/bar/menu/:id` | admin, owner | partial fields | `MenuItem` | `UPDATE bar_menu_items` | — |

### Bar Tables

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/bar/tables` | bar_staff, admin, owner | — | `Table[]` with current order info | `bar_tables LEFT JOIN bar_orders` | — |

### Bar Orders (Tabs)

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/bar/orders` | bar_staff, admin, owner | query: `?status=&table_id=` | `BarOrder[]` | `SELECT * FROM bar_orders` | — |
| GET | `/bar/orders/:id` | bar_staff, admin, owner | — | `BarOrder` with items | JOIN bar_order_items | — |
| POST | `/bar/orders` | bar_staff, front_desk | `{ table_id, member_id? }` | `{ bar_order_id }` | `open_bar_tab()` | `TABLE_NOT_FOUND` |
| POST | `/bar/orders/:id/items` | bar_staff | `{ menu_item_id, quantity?, notes? }` | `{ item_id }` | `add_bar_item()` | `BAR_ORDER_NOT_FOUND`, `BAR_ORDER_CLOSED`, `MENU_ITEM_NOT_AVAILABLE` |
| POST | `/bar/orders/:id/close` | bar_staff, front_desk | `{ payment_method }` | `{ payment_id, total }` | `close_bar_tab()` | `BAR_ORDER_NOT_FOUND`, `BAR_ORDER_CLOSED` |

### Kitchen Display

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/bar/kitchen` | kitchen_staff, bar_staff, admin | — | `BarOrderItem[]` where `kitchen_status != 'served'` | `SELECT * FROM bar_order_items` | — |
| PATCH | `/bar/kitchen/:item_id` | kitchen_staff, bar_staff | `{ kitchen_status }` | `BarOrderItem` | `UPDATE bar_order_items` | — |

---

## Module D — Finance, Staff & Admin (Developer 4)

### Payments & Dashboard

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/payments` | manager, admin, owner | query: `?source=&method=&from=&to=&member_id=` | `Payment[]` | `SELECT * FROM payments` | — |
| GET | `/dashboard/revenue` | manager, admin, owner | query: `?period=today\|week\|month` | `{ total, by_source: {}, by_method: {}, daily: [] }` | `v_revenue_daily`, `v_revenue_by_source` | — |
| GET | `/dashboard/summary` | manager, admin, owner | — | `{ active_members, expiring_soon, total_revenue_month, low_stock_count, open_tabs, today_bookings }` | Multiple views | — |
| GET | `/dashboard/low-stock` | manager, admin, owner, shop_staff | — | `Product[]` | `v_low_stock` | — |
| GET | `/dashboard/members` | manager, admin, owner | — | `MemberStatus[]` | `v_member_status` | — |

### Invoices

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/invoices` | admin, owner | query: `?status=&member_id=` | `Invoice[]` | `SELECT * FROM invoices` | — |
| GET | `/invoices/:id` | admin, owner | — | `Invoice` with items | JOIN invoice_items | — |
| POST | `/invoices` | admin, owner | `{ member_id?, client_name?, items: [{ description, quantity, unit_price }], due_date?, notes? }` | `Invoice` | `INSERT INTO invoices + invoice_items` | — |
| PATCH | `/invoices/:id` | admin, owner | `{ status?, notes? }` | `Invoice` | `UPDATE invoices` | — |
| POST | `/invoices/:id/pay` | admin, owner | `{ payment_method }` | `{ payment_id }` | `record_payment('invoice', ...)` | — |

### Staff

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/staff` | manager, admin, owner | — | `Staff[]` | `SELECT * FROM staff` | — |
| GET | `/staff/:id` | manager, admin, owner | — | `Staff` | `SELECT * FROM staff WHERE id=` | — |
| POST | `/staff` | manager, admin, owner | `{ full_name, email, phone?, role, monthly_salary?, leave_balance? }` | `Staff` | `INSERT INTO staff` | — |
| PATCH | `/staff/:id` | manager, admin, owner | partial fields | `Staff` | `UPDATE staff` | — |

### Shifts

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/shifts` | manager, admin, owner, front_desk | query: `?staff_id=&date=&from=&to=` | `Shift[]` | `SELECT * FROM shifts` | — |
| POST | `/shifts` | manager, admin, owner | `{ staff_id, shift_date, start_time, end_time, notes? }` | `Shift` | `INSERT INTO shifts` | — |
| PATCH | `/shifts/:id` | manager, admin, owner | partial fields | `Shift` | `UPDATE shifts` | — |
| DELETE | `/shifts/:id` | manager, admin, owner | — | `{ success: true }` | `DELETE FROM shifts` | — |

### Leave Requests

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/leave` | manager, admin, owner | query: `?status=&staff_id=` | `LeaveRequest[]` | `SELECT * FROM leave_requests` | — |
| POST | `/leave` | all staff | `{ start_date, end_date, reason? }` | `LeaveRequest` | `INSERT INTO leave_requests` | — |
| PATCH | `/leave/:id` | manager, admin, owner | `{ status, approved_by? }` | `LeaveRequest` | `UPDATE leave_requests` | — |

### Payroll

| Method | Path | Role | Request Body | Response | SQL / Table | Errors |
|--------|------|------|-------------|----------|-------------|--------|
| GET | `/payroll` | admin, owner | query: `?month=&staff_id=` | `Payroll[]` | `SELECT * FROM payroll` | — |
| POST | `/payroll/generate` | admin, owner | `{ month }` (YYYY-MM-DD, first of month) | `Payroll[]` | Bulk INSERT from staff salaries | — |
| PATCH | `/payroll/:id` | admin, owner | `{ status, deductions? }` | `Payroll` | `UPDATE payroll` | — |

---

## React Route Map (Recommended)

```
/                          → Public landing page (plans, about)
/courts                    → Public court availability
/shop                      → Public product catalog
/enquiry                   → Public lead/enquiry form
/login                     → Staff login

/app/dashboard             → Owner dashboard (Module D)
/app/members               → Member list + search (Module A)
/app/members/:id           → Member profile + history (Module A)
/app/members/new           → Register new member (Module A)
/app/leads                 → Leads list (Module A)
/app/bookings              → Booking calendar (Module B)
/app/bookings/new          → New booking flow (Module B)
/app/courts                → Court management (Module B)
/app/shop                  → Shop POS (Module C)
/app/shop/products         → Product management (Module C)
/app/shop/orders           → Order list (Module C)
/app/bar                   → Bar order screen + table map (Module C)
/app/bar/kitchen           → Kitchen display (Module C)
/app/invoices              → Invoice list (Module D)
/app/invoices/:id          → Invoice detail (Module D)
/app/staff                 → Staff management (Module D)
/app/staff/shifts           → Shift schedule (Module D)
/app/staff/leave            → Leave requests (Module D)
/app/staff/payroll          → Payroll (Module D)
/app/reports               → Revenue reports (Module D)
```

---

## .env Template

```env
# Supabase
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJ...your-service-role-key
SUPABASE_ANON_KEY=eyJ...your-anon-key

# Backend
PORT=3000
NODE_ENV=development
JWT_SECRET=change-me-in-production
CLUB_TIMEZONE=Asia/Kolkata

# Frontend (Vite)
VITE_API_URL=http://localhost:3000/api
VITE_SUPABASE_URL=https://your-project.supabase.co
VITE_SUPABASE_ANON_KEY=eyJ...your-anon-key
```
