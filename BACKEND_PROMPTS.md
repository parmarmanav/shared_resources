# Node.js Backend Prompts for 4 Developers

These 4 prompts are designed to be handed out to 4 developers (or fed sequentially into an AI) to build the entire Node.js Express backend. 

**Prerequisites:** 
- Make sure you have created a `backend` folder inside your project.
- You have your Supabase URL and Service Role Key ready from the Supabase dashboard.
- The `schema.sql` and `seed.sql` have already been run in your Supabase database.

---

## 📋 PROMPT 1: Dev 1 (Project Setup, Auth, & Module A)
**Role:** Lead Backend Developer / Module A (Members & Leads)

**Your Goal:** Initialize the Express project, configure Supabase Auth (Google Sign-In) validation, and build the Members and Leads APIs.

**Step-by-Step Instructions:**
1. **Initialize the Project:**
   - In the `backend/` folder, run `npm init -y`.
   - In `package.json`, add `"type": "module"` so we can use modern `import` syntax.
   - Run `npm install express cors dotenv @supabase/supabase-js morgan`.
   - Run `npm install -D nodemon` and add `"dev": "nodemon server.js"` to your package.json scripts.

2. **Setup Folder Structure:**
   Create the following folders:
   - `src/config/`
   - `src/middleware/`
   - `src/routes/v1/`

3. **Configure Supabase (`src/config/supabase.js`):**
   - Import `createClient` from `@supabase/supabase-js`.
   - Initialize and export a client using `process.env.SUPABASE_URL` and `process.env.SUPABASE_SERVICE_ROLE_KEY`. (We are using the service role key to bypass RLS, as all business logic is handled in Express).

4. **Build the Auth Middleware (`src/middleware/auth.js`):**
   - Create a middleware function `verifySupabaseToken(req, res, next)`.
   - Extract the token from `req.headers.authorization` (format: `Bearer <token>`). If missing, return 401 Unauthorized.
   - Use `await supabase.auth.getUser(token)` to verify it. If error, return 401.
   - Using the email from `user.email`, query our custom table: `await supabase.from('staff').select('*').eq('email', user.email).single()`.
   - If no staff record is found, return 403 Forbidden (meaning a non-staff member tried to hit the API).
   - Attach the staff record to the request: `req.user = staff;` and call `next()`.
   - Export a second helper: `authorizeRoles(...allowedRoles)` that checks if `req.user.role` is in the allowed list, returning 403 if not.

5. **Build Module A Routes (`src/routes/v1/members.js`, `plans.js`, `leads.js`):**
   - Protect all routes with `verifySupabaseToken`.
   - **Members:** Implement GET `/`, GET `/:id`, POST `/` (calls `supabase.rpc('register_member')`), PATCH `/:id`.
   - **Members Entitlements:** GET `/:id/entitlements` must call `supabase.rpc('get_entitlements', { p_member_id: req.params.id })`.
   - **Leads:** Implement GET `/`, POST `/`, PATCH `/:id`, and POST `/:id/convert` (which calls `supabase.rpc('convert_lead')`).

6. **Create `server.js`:**
   - Initialize Express, apply `cors()`, `express.json()`, and `morgan('dev')`.
   - Mount the routes: `app.use('/api/v1/members', membersRouter);` etc.
   - Add a global error handler at the bottom. Start the server on `process.env.PORT || 3000`.

---

## 📋 PROMPT 2: Dev 2 (Module B - Courts & Bookings)
**Role:** Backend Developer (Courts & Bookings)

**Your Goal:** Build the scheduling and court booking engine. Assume the Express server and `supabase.js` client are already set up by Dev 1.

**Step-by-Step Instructions:**
1. **Understand the Architecture:** 
   - We use pre-generated slots (`court_slots`) and map `bookings` to them.
   - All routes you build must be protected by the `verifySupabaseToken` middleware created by Dev 1.

2. **Build Sports & Courts Routes (`src/routes/v1/sports.js`, `courts.js`):**
   - Implement simple CRUD operations for `sports` and `courts` tables using `supabase.from()`.

3. **Build Slots Availability (`src/routes/v1/slots.js`):**
   - This is the most complex GET query. You need to return available slots for a specific date.
   - Query `court_slots` for a specific date, and `LEFT JOIN` the `bookings` table. 
   - A slot is "available" if there is no confirmed booking attached to it (unless `is_social` is true, then it's always available). 
   - Shape the JSON response so the frontend can easily render a daily calendar grid.

4. **Build Booking Engine (`src/routes/v1/bookings.js`):**
   - **POST `/` (Create Booking):** 
     - Extract `slot_id`, `member_id` (optional), `walker_name`, etc., from `req.body`.
     - Execute `const { data: booking_id, error } = await supabase.rpc('book_court', { ...args, p_staff_id: req.user.id })`.
     - **CRITICAL:** If `book_court` succeeds, you MUST immediately record the payment: `await supabase.rpc('record_payment', { p_source: 'court', p_reference_id: booking_id, p_amount: <amount_from_frontend_or_db>, p_method: req.body.payment_method })`.
     - Handle Postgres exceptions! If `error.message` contains `SLOT_TAKEN` or `DAILY_LIMIT_REACHED`, return a 409 Conflict status to the frontend.
   - **POST `/:id/cancel`:**
     - Call `supabase.rpc('cancel_booking', { p_booking_id: req.params.id })`.

---

## 📋 PROMPT 3: Dev 3 (Module C - Shop & Bar)
**Role:** Backend Developer (POS & Inventory)

**Your Goal:** Build the Point of Sale backend for both retail (Shop) and F&B (Bar). Assume Express and Auth are already set up.

**Step-by-Step Instructions:**
1. **Build Shop Inventory (`src/routes/v1/shop.js`):**
   - Implement GET routes for `product_categories` and `products`. 
   - For `GET /products`, support query filters like `?in_stock=true` and `?category_id=...`.
   - Implement a route to adjust stock: `PATCH /products/:id/stock` which increments/decrements `stock_qty`.

2. **Build Shop Orders:**
   - **POST `/orders` (Checkout):** The frontend will send an array of items `[{ product_id, quantity }]`.
   - Call `await supabase.rpc('place_shop_order', { p_items: req.body.items, ... })`.
   - This RPC automatically decrements stock. 
   - If successful, immediately call `supabase.rpc('record_payment')` using the returned order ID. Handle `OUT_OF_STOCK` errors by returning a 409 status.

3. **Build Bar Menu & Tables (`src/routes/v1/bar.js`):**
   - Implement standard GET routes for `bar_menu_categories`, `bar_menu_items`, and `bar_tables`.
   - Include a query on `bar_tables` to fetch the currently 'open' `bar_orders` so the frontend knows which tables are occupied.

4. **Build Bar Tabs (The tricky part):**
   - **POST `/bar/orders` (Open Tab):** Calls `supabase.rpc('open_bar_tab', { p_table_id: req.body.table_id })`.
   - **POST `/bar/orders/:id/items` (Add Item):** Calls `supabase.rpc('add_bar_item')`.
   - **POST `/bar/orders/:id/close` (Close & Pay):** Calls `supabase.rpc('close_bar_tab')`. This automatically triggers the `record_payment` function in SQL.

5. **Kitchen Display System (KDS):**
   - **GET `/bar/kitchen`:** Query `bar_order_items` where `kitchen_status` is NOT 'served'. 
   - **PATCH `/bar/kitchen/:item_id`:** Update the `kitchen_status` (ordered -> preparing -> ready -> served).

---

## 📋 PROMPT 4: Dev 4 (Module D - Admin, Staff & Analytics)
**Role:** Backend Developer (Admin & Analytics)

**Your Goal:** Build the HR, Payroll, and Financial Dashboard endpoints. Assume Express and Auth are set up. Only `owner` and `admin` roles should access most of these.

**Step-by-Step Instructions:**
1. **Protect Your Routes:**
   - Use the `authorizeRoles('admin', 'owner')` middleware exported by Dev 1 on all these routes (except maybe GET `/staff` where managers need access).

2. **Build Dashboard Analytics (`src/routes/v1/dashboard.js`):**
   - We created SQL Views exactly for this. You do not need to write complex group-by logic in JS.
   - **GET `/revenue`:** Simply run `supabase.from('v_revenue_daily').select('*')` and return the data.
   - **GET `/low-stock`:** Run `supabase.from('v_low_stock').select('*')`.
   - **GET `/members-status`:** Run `supabase.from('v_member_status').select('*')`.

3. **Build Staff & HR (`src/routes/v1/staff.js`, `shifts.js`, `leave.js`):**
   - Standard CRUD operations on the `staff`, `shifts`, and `leave_requests` tables.
   - Remember, the `staff` table does NOT contain passwords anymore since we use Supabase Auth. It only tracks their role, salary, and leave balance.

4. **Build Payroll Generator (`src/routes/v1/payroll.js`):**
   - **POST `/payroll/generate`:** 
     - Receive a `month` (e.g., '2026-10-01') in the body.
     - Query all active staff from the `staff` table where `monthly_salary > 0`.
     - Loop through them and construct an array of objects to insert into the `payroll` table: `{ staff_id, month, gross_salary, net_salary, status: 'pending' }`.
     - Perform a bulk insert via `supabase.from('payroll').insert(payrollArray)`.

5. **Build Invoicing (`src/routes/v1/invoices.js`):**
   - **POST `/invoices`:** Insert into `invoices`, grab the returned ID, then bulk insert into `invoice_items`. Calculate the totals inside Node.js before saving.
   - **POST `/invoices/:id/pay`:** Mark the invoice status as 'paid' and call `supabase.rpc('record_payment', { p_source: 'invoice', ... })`.
