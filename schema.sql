-- =============================================================================
-- Champions Club — schema.sql
-- Supabase Postgres, runnable top-to-bottom
-- RLS is SKIPPED — backend uses the service-role key for all access.
-- All timestamps are stored as TIMESTAMPTZ; club-local logic uses Asia/Kolkata.
-- =============================================================================

-- ─── Extensions ──────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";    -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "btree_gist";  -- for exclusion constraints on bookings

-- =============================================================================
-- MODULE A — Members & Plans  (Developer 1)
-- =============================================================================

-- Plans: Gold, Silver, Junior — all entitlements are DATA, not code.
CREATE TABLE plans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,          -- 'Gold', 'Silver', 'Junior'
    description     TEXT,
    court_rate       NUMERIC(10,2) NOT NULL,        -- per-session rate for members on this plan (0 = free)
    shop_discount_pct NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (shop_discount_pct >= 0 AND shop_discount_pct <= 100),
    bar_discount_pct  NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (bar_discount_pct >= 0 AND bar_discount_pct <= 100),
    daily_booking_limit INT NOT NULL DEFAULT 2,
    duration_months  INT NOT NULL DEFAULT 12,       -- default membership duration
    price           NUMERIC(10,2) NOT NULL,         -- membership fee
    is_junior        BOOLEAN NOT NULL DEFAULT FALSE, -- if true, member must be under 18
    trial_rate       NUMERIC(10,2) NOT NULL DEFAULT 0, -- rate for trial sessions
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Members
CREATE TABLE members (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       TEXT NOT NULL,
    email           TEXT UNIQUE,
    phone           TEXT NOT NULL,
    membership_code  TEXT UNIQUE,                       -- e.g., 'MEM-1042' for quick front-desk lookup
    photo_url       TEXT,                               -- profile photo for staff recognition
    date_of_birth   DATE,
    client_type     TEXT NOT NULL DEFAULT 'individual' CHECK (client_type IN ('individual', 'business')),
    plan_id         UUID REFERENCES plans(id),
    membership_start DATE,
    membership_expiry DATE,
    status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired', 'suspended')),
    address         TEXT,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_members_phone ON members(phone);
CREATE INDEX idx_members_email ON members(email);
CREATE INDEX idx_members_status ON members(status);
CREATE INDEX idx_members_plan ON members(plan_id);
CREATE INDEX idx_members_expiry ON members(membership_expiry);

-- Leads / Enquiries from the public website
CREATE TABLE leads (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       TEXT NOT NULL,
    email           TEXT,
    phone           TEXT NOT NULL,
    message         TEXT,
    source          TEXT NOT NULL DEFAULT 'website' CHECK (source IN ('website', 'phone', 'walk_in', 'referral')),
    status          TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new', 'contacted', 'quoted', 'converted', 'lost')),
    assigned_staff_id UUID,  -- FK to staff added after staff table
    converted_member_id UUID REFERENCES members(id),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_leads_status ON leads(status);

-- =============================================================================
-- MODULE B — Courts & Bookings  (Developer 2)
-- =============================================================================

-- Sports are configurable data (resolves tennis/cricket vs padel/badminton ambiguity)
CREATE TABLE sports (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,            -- 'Tennis', 'Cricket'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Courts
CREATE TABLE courts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,             -- 'Court 1', 'Court 2', 'Cricket Net 1'
    sport_id        UUID NOT NULL REFERENCES sports(id),
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    walk_in_rate    NUMERIC(10,2) NOT NULL,           -- rate for non-members
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_courts_sport ON courts(sport_id);

-- Court slots: pre-generated or on-demand time blocks.
-- Each slot = 1-hour session starting every 30 min.
-- The EXCLUSION constraint prevents two non-social, non-cancelled bookings on the same court at overlapping times.
CREATE TABLE court_slots (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    court_id        UUID NOT NULL REFERENCES courts(id),
    start_time      TIMESTAMPTZ NOT NULL,
    end_time        TIMESTAMPTZ NOT NULL,
    is_social       BOOLEAN NOT NULL DEFAULT FALSE,   -- social play: multiple people allowed
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_slot_duration CHECK (end_time = start_time + INTERVAL '1 hour'),
    CONSTRAINT uq_court_slot UNIQUE (court_id, start_time)
);

CREATE INDEX idx_court_slots_court_time ON court_slots(court_id, start_time);
CREATE INDEX idx_court_slots_start ON court_slots(start_time);

-- Bookings
CREATE TABLE bookings (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    slot_id         UUID NOT NULL REFERENCES court_slots(id),
    member_id       UUID REFERENCES members(id),      -- NULL for walk-ins
    walker_name     TEXT,                              -- name for walk-in guests
    walker_phone    TEXT,                              -- phone for walk-in guests
    is_trial        BOOLEAN NOT NULL DEFAULT FALSE,
    price_charged   NUMERIC(10,2) NOT NULL,            -- snapshot at booking time
    status          TEXT NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed', 'cancelled', 'completed', 'no_show')),
    booked_by_staff_id UUID,                           -- FK to staff
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    cancelled_at    TIMESTAMPTZ
);

CREATE INDEX idx_bookings_slot ON bookings(slot_id);
CREATE INDEX idx_bookings_member ON bookings(member_id);
CREATE INDEX idx_bookings_status ON bookings(status);

-- Double-booking prevention at the DATABASE level (safety net beyond book_court()).
-- For non-social slots: only one confirmed booking per slot.
-- For social slots: multiple confirmed bookings allowed.
-- Implemented as a BEFORE INSERT trigger since partial unique indexes can't reference other tables.

CREATE OR REPLACE FUNCTION trg_prevent_double_booking()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_court_id  UUID;
    v_start     TIMESTAMPTZ;
    v_end       TIMESTAMPTZ;
    v_is_social BOOLEAN;
BEGIN
    -- Only check confirmed bookings
    IF NEW.status != 'confirmed' THEN
        RETURN NEW;
    END IF;

    -- Get full slot details (court + time range + social flag)
    SELECT cs.court_id, cs.start_time, cs.end_time, cs.is_social
    INTO v_court_id, v_start, v_end, v_is_social
    FROM court_slots cs WHERE cs.id = NEW.slot_id;

    -- For non-social slots, ensure no other confirmed booking OVERLAPS
    -- on the same court (prevents 6:00-7:00 vs 6:30-7:30 clash)
    IF NOT v_is_social THEN
        IF EXISTS (
            SELECT 1 FROM bookings b
            JOIN court_slots cs ON b.slot_id = cs.id
            WHERE cs.court_id = v_court_id
              AND b.status = 'confirmed'
              AND NOT cs.is_social
              AND b.id != COALESCE(NEW.id, '00000000-0000-0000-0000-000000000000'::UUID)
              AND cs.start_time < v_end      -- overlap check: other starts before this ends
              AND cs.end_time   > v_start    -- overlap check: other ends after this starts
        ) THEN
            RAISE EXCEPTION 'SLOT_TAKEN' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bookings_prevent_double
    BEFORE INSERT OR UPDATE ON bookings
    FOR EACH ROW
    EXECUTE FUNCTION trg_prevent_double_booking();


-- =============================================================================
-- MODULE C — Shop & Bar  (Developer 3)
-- =============================================================================

-- ─── Shop ────────────────────────────────────────────────────────────────────

CREATE TABLE product_categories (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,             -- 'Rackets', 'Balls', 'Shoes', 'Accessories', 'Apparel'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE products (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id     UUID NOT NULL REFERENCES product_categories(id),
    name            TEXT NOT NULL,
    description     TEXT,
    price           NUMERIC(10,2) NOT NULL,
    stock_qty       INT NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
    low_stock_threshold INT NOT NULL DEFAULT 5,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    image_url       TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_products_stock ON products(stock_qty) WHERE is_active = TRUE;

-- Shop orders (both in-store and online share this table)
CREATE TABLE orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    member_id       UUID REFERENCES members(id),       -- NULL for non-member purchases
    channel         TEXT NOT NULL CHECK (channel IN ('in_store', 'online')),
    fulfilment_type TEXT NOT NULL DEFAULT 'immediate' CHECK (fulfilment_type IN ('immediate', 'pickup', 'delivery')),
    delivery_address TEXT,                              -- for delivery orders
    guest_name      TEXT,                               -- for non-member online orders
    guest_phone     TEXT,                               -- contact for non-member orders
    guest_email     TEXT,                               -- contact for non-member orders
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'ready', 'fulfilled', 'cancelled')),
    discount_pct    NUMERIC(5,2) NOT NULL DEFAULT 0,    -- snapshot of member discount
    subtotal        NUMERIC(10,2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    total           NUMERIC(10,2) NOT NULL DEFAULT 0,
    placed_by_staff_id UUID,                            -- FK to staff
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_member ON orders(member_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_channel ON orders(channel);

CREATE TABLE order_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    order_id        UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES products(id),
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL,            -- price snapshot
    line_total      NUMERIC(10,2) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_items_order ON order_items(order_id);

-- ─── Bar ─────────────────────────────────────────────────────────────────────

CREATE TABLE bar_menu_categories (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            TEXT NOT NULL UNIQUE,              -- 'Drinks', 'Starters', 'Mains', 'Desserts'
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE bar_menu_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    category_id     UUID NOT NULL REFERENCES bar_menu_categories(id),
    name            TEXT NOT NULL,
    description     TEXT,
    price           NUMERIC(10,2) NOT NULL,
    is_available    BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bar_menu_items_category ON bar_menu_items(category_id);

CREATE TABLE bar_tables (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_number    INT NOT NULL UNIQUE,
    seats           INT NOT NULL DEFAULT 4,
    status          TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'occupied', 'reserved')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Bar orders (tabs)
CREATE TABLE bar_orders (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    table_id        UUID REFERENCES bar_tables(id),
    member_id       UUID REFERENCES members(id),       -- for discount; NULL = guest
    status          TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'closed', 'cancelled')),
    discount_pct    NUMERIC(5,2) NOT NULL DEFAULT 0,    -- snapshot of member bar discount
    subtotal        NUMERIC(10,2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
    total           NUMERIC(10,2) NOT NULL DEFAULT 0,
    served_by_staff_id UUID,                            -- FK to staff
    opened_at       TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    closed_at       TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bar_orders_table ON bar_orders(table_id);
CREATE INDEX idx_bar_orders_member ON bar_orders(member_id);
CREATE INDEX idx_bar_orders_status ON bar_orders(status);

CREATE TABLE bar_order_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    bar_order_id    UUID NOT NULL REFERENCES bar_orders(id) ON DELETE CASCADE,
    menu_item_id    UUID NOT NULL REFERENCES bar_menu_items(id),
    quantity        INT NOT NULL CHECK (quantity > 0),
    unit_price      NUMERIC(10,2) NOT NULL,             -- price snapshot
    line_total      NUMERIC(10,2) NOT NULL,
    kitchen_status  TEXT NOT NULL DEFAULT 'ordered' CHECK (kitchen_status IN ('ordered', 'preparing', 'ready', 'served')),
    notes           TEXT,                                -- special instructions
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_bar_order_items_order ON bar_order_items(bar_order_id);
CREATE INDEX idx_bar_order_items_kitchen ON bar_order_items(kitchen_status);


-- =============================================================================
-- MODULE D — Finance, Staff & Admin  (Developer 4)
-- =============================================================================

-- Staff (also used as "users" of the system for auth)
CREATE TABLE staff (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name       TEXT NOT NULL,
    email           TEXT UNIQUE NOT NULL,
    phone           TEXT,
    role            TEXT NOT NULL CHECK (role IN ('admin', 'manager', 'front_desk', 'bar_staff', 'kitchen_staff', 'shop_staff', 'owner')),
    password_hash   TEXT,                               -- for auth (bcrypt)
    monthly_salary  NUMERIC(10,2),
    leave_balance   INT NOT NULL DEFAULT 12,            -- annual leave days
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_staff_role ON staff(role);
CREATE INDEX idx_staff_email ON staff(email);

-- Now add FK for leads.assigned_staff_id
ALTER TABLE leads ADD CONSTRAINT fk_leads_staff FOREIGN KEY (assigned_staff_id) REFERENCES staff(id);
-- Add FK for bookings.booked_by_staff_id
ALTER TABLE bookings ADD CONSTRAINT fk_bookings_staff FOREIGN KEY (booked_by_staff_id) REFERENCES staff(id);
-- Add FK for orders.placed_by_staff_id
ALTER TABLE orders ADD CONSTRAINT fk_orders_staff FOREIGN KEY (placed_by_staff_id) REFERENCES staff(id);
-- Add FK for bar_orders.served_by_staff_id
ALTER TABLE bar_orders ADD CONSTRAINT fk_bar_orders_staff FOREIGN KEY (served_by_staff_id) REFERENCES staff(id);

-- Shifts
CREATE TABLE shifts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id        UUID NOT NULL REFERENCES staff(id),
    shift_date      DATE NOT NULL,
    start_time      TIME NOT NULL,
    end_time        TIME NOT NULL,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_shifts_staff ON shifts(staff_id);
CREATE INDEX idx_shifts_date ON shifts(shift_date);

-- Leave requests
CREATE TABLE leave_requests (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id        UUID NOT NULL REFERENCES staff(id),
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL,
    reason          TEXT,
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    approved_by     UUID REFERENCES staff(id),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_leave_staff ON leave_requests(staff_id);
CREATE INDEX idx_leave_status ON leave_requests(status);

-- Payroll
CREATE TABLE payroll (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    staff_id        UUID NOT NULL REFERENCES staff(id),
    month           DATE NOT NULL,                      -- first of the month, e.g. 2026-10-01
    gross_salary    NUMERIC(10,2) NOT NULL,
    deductions      NUMERIC(10,2) NOT NULL DEFAULT 0,
    net_salary      NUMERIC(10,2) NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'paid')),
    paid_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT uq_payroll_staff_month UNIQUE (staff_id, month)
);

-- ─── Unified Payments Ledger ─────────────────────────────────────────────────
-- ONE table for ALL revenue. Dashboard queries go here.
CREATE TABLE payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    source          TEXT NOT NULL CHECK (source IN ('court', 'shop', 'bar', 'membership', 'invoice')),
    reference_id    UUID NOT NULL,                      -- FK to the source record (booking, order, bar_order, member, invoice)
    member_id       UUID REFERENCES members(id),
    amount          NUMERIC(10,2) NOT NULL,
    method          TEXT NOT NULL CHECK (method IN ('cash', 'card', 'upi')),
    received_by_staff_id UUID REFERENCES staff(id),
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_source ON payments(source);
CREATE INDEX idx_payments_member ON payments(member_id);
CREATE INDEX idx_payments_method ON payments(method);
CREATE INDEX idx_payments_created ON payments(created_at);

-- Invoices (for memberships, business clients)
CREATE TABLE invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_number  TEXT NOT NULL UNIQUE,
    member_id       UUID REFERENCES members(id),
    client_name     TEXT,                               -- for non-member business clients
    status          TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'paid', 'overdue', 'cancelled')),
    subtotal        NUMERIC(10,2) NOT NULL DEFAULT 0,
    tax_amount      NUMERIC(10,2) NOT NULL DEFAULT 0,
    total           NUMERIC(10,2) NOT NULL DEFAULT 0,
    due_date        DATE,
    paid_at         TIMESTAMPTZ,
    notes           TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invoices_member ON invoices(member_id);
CREATE INDEX idx_invoices_status ON invoices(status);

CREATE TABLE invoice_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id      UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    description     TEXT NOT NULL,
    quantity        INT NOT NULL DEFAULT 1,
    unit_price      NUMERIC(10,2) NOT NULL,
    line_total      NUMERIC(10,2) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invoice_items_invoice ON invoice_items(invoice_id);


-- =============================================================================
-- SHARED HELPER FUNCTIONS  (plpgsql, called via supabase rpc())
-- =============================================================================

-- ─── get_entitlements ─────────────────────────────────────────────────────────
-- Returns the plan entitlements for a member. Used by Modules B, C.
-- Owner: Module A (Developer 1)
CREATE OR REPLACE FUNCTION get_entitlements(p_member_id UUID)
RETURNS TABLE (
    plan_name TEXT,
    court_rate NUMERIC,
    shop_discount_pct NUMERIC,
    bar_discount_pct NUMERIC,
    daily_booking_limit INT,
    is_active BOOLEAN
) LANGUAGE plpgsql AS $$
BEGIN
    RETURN QUERY
    SELECT
        p.name,
        p.court_rate,
        p.shop_discount_pct,
        p.bar_discount_pct,
        p.daily_booking_limit,
        (m.status = 'active' AND m.membership_expiry >= CURRENT_DATE) AS is_active
    FROM members m
    JOIN plans p ON m.plan_id = p.id
    WHERE m.id = p_member_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'MEMBER_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;
END;
$$;

-- ─── record_payment ──────────────────────────────────────────────────────────
-- Central function to record any payment. Used by Modules A, B, C.
-- Owner: Module D (Developer 4)
CREATE OR REPLACE FUNCTION record_payment(
    p_source TEXT,
    p_reference_id UUID,
    p_amount NUMERIC,
    p_method TEXT,
    p_member_id UUID DEFAULT NULL,
    p_staff_id UUID DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_payment_id UUID;
BEGIN
    -- Validate source
    IF p_source NOT IN ('court', 'shop', 'bar', 'membership', 'invoice') THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_SOURCE' USING ERRCODE = 'P0001';
    END IF;
    -- Validate method
    IF p_method NOT IN ('cash', 'card', 'upi') THEN
        RAISE EXCEPTION 'INVALID_PAYMENT_METHOD' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, notes)
    VALUES (p_source, p_reference_id, p_amount, p_method, p_member_id, p_staff_id, p_notes)
    RETURNING id INTO v_payment_id;

    RETURN v_payment_id;
END;
$$;


-- =============================================================================
-- MODULE B FUNCTIONS — Court Booking Logic  (Developer 2)
-- =============================================================================

-- ─── book_court ──────────────────────────────────────────────────────────────
-- Atomically books a court slot. Enforces:
--   1. Slot exists and is in the future
--   2. For non-social slots: no other confirmed booking exists (row lock)
--   3. Per-member daily limit (default 2)
--   4. Price snapshot based on member plan or walk-in rate
-- Returns the booking ID.
CREATE OR REPLACE FUNCTION book_court(
    p_slot_id UUID,
    p_member_id UUID DEFAULT NULL,
    p_walker_name TEXT DEFAULT NULL,
    p_walker_phone TEXT DEFAULT NULL,
    p_is_trial BOOLEAN DEFAULT FALSE,
    p_staff_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_slot RECORD;
    v_booking_id UUID;
    v_price NUMERIC(10,2);
    v_daily_count INT;
    v_daily_limit INT := 2;
    v_court_rate NUMERIC(10,2);
    v_slot_date DATE;
BEGIN
    -- 1. Lock the slot row to prevent concurrent bookings
    SELECT cs.*, c.walk_in_rate
    INTO v_slot
    FROM court_slots cs
    JOIN courts c ON cs.court_id = c.id
    WHERE cs.id = p_slot_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SLOT_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;

    -- Must be in the future
    IF v_slot.start_time <= NOW() THEN
        RAISE EXCEPTION 'SLOT_IN_PAST' USING ERRCODE = 'P0001';
    END IF;

    -- 2. For non-social slots, check no overlapping confirmed booking on the same court
    IF NOT v_slot.is_social THEN
        IF EXISTS (
            SELECT 1 FROM bookings b
            JOIN court_slots cs ON b.slot_id = cs.id
            WHERE cs.court_id = v_slot.court_id
              AND b.status = 'confirmed'
              AND NOT cs.is_social
              AND cs.start_time < v_slot.end_time
              AND cs.end_time   > v_slot.start_time
        ) THEN
            RAISE EXCEPTION 'SLOT_TAKEN' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    -- 3. Determine price and daily limit
    v_slot_date := (v_slot.start_time AT TIME ZONE 'Asia/Kolkata')::DATE;

    IF p_member_id IS NOT NULL THEN
        -- Get member entitlements
        SELECT p.court_rate, p.daily_booking_limit
        INTO v_court_rate, v_daily_limit
        FROM members m
        JOIN plans p ON m.plan_id = p.id
        WHERE m.id = p_member_id
          AND m.status = 'active'
          AND m.membership_expiry >= CURRENT_DATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'MEMBER_NOT_ACTIVE' USING ERRCODE = 'P0001';
        END IF;

        -- Check daily booking limit
        SELECT COUNT(*) INTO v_daily_count
        FROM bookings b
        JOIN court_slots cs2 ON b.slot_id = cs2.id
        WHERE b.member_id = p_member_id
          AND b.status = 'confirmed'
          AND (cs2.start_time AT TIME ZONE 'Asia/Kolkata')::DATE = v_slot_date;

        IF v_daily_count >= v_daily_limit THEN
            RAISE EXCEPTION 'DAILY_LIMIT_REACHED' USING ERRCODE = 'P0001';
        END IF;

        -- Price: use plan court_rate, or trial_rate if trial
        IF p_is_trial THEN
            SELECT p.trial_rate INTO v_price
            FROM members m JOIN plans p ON m.plan_id = p.id
            WHERE m.id = p_member_id;
        ELSE
            v_price := v_court_rate;
        END IF;
    ELSE
        -- Walk-in: use court's walk-in rate
        v_price := v_slot.walk_in_rate;
        IF p_is_trial THEN
            v_price := 0; -- trial sessions are free for walk-ins too
        END IF;
    END IF;

    -- 4. Create the booking
    INSERT INTO bookings (slot_id, member_id, walker_name, walker_phone, is_trial, price_charged, status, booked_by_staff_id)
    VALUES (p_slot_id, p_member_id, p_walker_name, p_walker_phone, p_is_trial, v_price, 'confirmed', p_staff_id)
    RETURNING id INTO v_booking_id;

    RETURN v_booking_id;
END;
$$;

-- ─── cancel_booking ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION cancel_booking(p_booking_id UUID)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
    UPDATE bookings
    SET status = 'cancelled', cancelled_at = NOW()
    WHERE id = p_booking_id AND status = 'confirmed';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BOOKING_NOT_FOUND_OR_ALREADY_CANCELLED' USING ERRCODE = 'P0001';
    END IF;
END;
$$;


-- =============================================================================
-- MODULE C FUNCTIONS — Shop & Bar Logic  (Developer 3)
-- =============================================================================

-- ─── place_shop_order ────────────────────────────────────────────────────────
-- Creates a shop order with line items. Atomically decrements stock.
-- p_items: JSONB array of { product_id, quantity }
CREATE OR REPLACE FUNCTION place_shop_order(
    p_member_id UUID DEFAULT NULL,
    p_channel TEXT DEFAULT 'in_store',
    p_fulfilment_type TEXT DEFAULT 'immediate',
    p_delivery_address TEXT DEFAULT NULL,
    p_guest_name TEXT DEFAULT NULL,
    p_guest_phone TEXT DEFAULT NULL,
    p_guest_email TEXT DEFAULT NULL,
    p_items JSONB DEFAULT '[]',
    p_staff_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_order_id UUID;
    v_item RECORD;
    v_product RECORD;
    v_discount_pct NUMERIC(5,2) := 0;
    v_subtotal NUMERIC(10,2) := 0;
    v_line_total NUMERIC(10,2);
    v_discount_amount NUMERIC(10,2);
BEGIN
    -- Get member discount if applicable
    IF p_member_id IS NOT NULL THEN
        SELECT p.shop_discount_pct INTO v_discount_pct
        FROM members m JOIN plans p ON m.plan_id = p.id
        WHERE m.id = p_member_id
          AND m.status = 'active'
          AND m.membership_expiry >= CURRENT_DATE;
        -- If member not found/inactive, just use 0 discount (don't block purchase)
        IF NOT FOUND THEN
            v_discount_pct := 0;
        END IF;
    END IF;

    -- Create order
    INSERT INTO orders (member_id, channel, fulfilment_type, delivery_address, guest_name, guest_phone, guest_email, discount_pct, placed_by_staff_id)
    VALUES (p_member_id, p_channel, p_fulfilment_type, p_delivery_address, p_guest_name, p_guest_phone, p_guest_email, v_discount_pct, p_staff_id)
    RETURNING id INTO v_order_id;

    -- Process each item
    FOR v_item IN SELECT * FROM jsonb_to_recordset(p_items) AS x(product_id UUID, quantity INT)
    LOOP
        -- Lock product row and check stock
        SELECT * INTO v_product
        FROM products
        WHERE id = v_item.product_id AND is_active = TRUE
        FOR UPDATE;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'PRODUCT_NOT_FOUND' USING ERRCODE = 'P0001';
        END IF;

        -- Atomic stock decrement
        UPDATE products
        SET stock_qty = stock_qty - v_item.quantity,
            updated_at = NOW()
        WHERE id = v_item.product_id
          AND stock_qty >= v_item.quantity;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'OUT_OF_STOCK' USING ERRCODE = 'P0001';
        END IF;

        v_line_total := v_product.price * v_item.quantity;
        v_subtotal := v_subtotal + v_line_total;

        INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total)
        VALUES (v_order_id, v_item.product_id, v_item.quantity, v_product.price, v_line_total);
    END LOOP;

    -- Calculate totals
    v_discount_amount := ROUND(v_subtotal * v_discount_pct / 100, 2);

    UPDATE orders
    SET subtotal = v_subtotal,
        discount_amount = v_discount_amount,
        total = v_subtotal - v_discount_amount,
        status = 'confirmed',
        updated_at = NOW()
    WHERE id = v_order_id;

    RETURN v_order_id;
END;
$$;

-- ─── open_bar_tab ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION open_bar_tab(
    p_table_id UUID,
    p_member_id UUID DEFAULT NULL,
    p_staff_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_order_id UUID;
    v_discount_pct NUMERIC(5,2) := 0;
BEGIN
    -- Check table is available or already occupied (allow adding to existing)
    UPDATE bar_tables SET status = 'occupied' WHERE id = p_table_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'TABLE_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;

    -- Get member bar discount
    IF p_member_id IS NOT NULL THEN
        SELECT p.bar_discount_pct INTO v_discount_pct
        FROM members m JOIN plans p ON m.plan_id = p.id
        WHERE m.id = p_member_id
          AND m.status = 'active'
          AND m.membership_expiry >= CURRENT_DATE;
        IF NOT FOUND THEN
            v_discount_pct := 0;
        END IF;
    END IF;

    INSERT INTO bar_orders (table_id, member_id, discount_pct, served_by_staff_id)
    VALUES (p_table_id, p_member_id, v_discount_pct, p_staff_id)
    RETURNING id INTO v_order_id;

    RETURN v_order_id;
END;
$$;

-- ─── add_bar_item ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION add_bar_item(
    p_bar_order_id UUID,
    p_menu_item_id UUID,
    p_quantity INT DEFAULT 1,
    p_notes TEXT DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_item_id UUID;
    v_price NUMERIC(10,2);
    v_order_status TEXT;
BEGIN
    -- Verify order is open
    SELECT status INTO v_order_status FROM bar_orders WHERE id = p_bar_order_id FOR UPDATE;
    IF v_order_status IS NULL THEN
        RAISE EXCEPTION 'BAR_ORDER_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;
    IF v_order_status != 'open' THEN
        RAISE EXCEPTION 'BAR_ORDER_CLOSED' USING ERRCODE = 'P0001';
    END IF;

    -- Get menu item price
    SELECT price INTO v_price FROM bar_menu_items WHERE id = p_menu_item_id AND is_available = TRUE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'MENU_ITEM_NOT_AVAILABLE' USING ERRCODE = 'P0001';
    END IF;

    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, notes)
    VALUES (p_bar_order_id, p_menu_item_id, p_quantity, v_price, v_price * p_quantity, p_notes)
    RETURNING id INTO v_item_id;

    -- Update order subtotal
    UPDATE bar_orders
    SET subtotal = (SELECT COALESCE(SUM(line_total), 0) FROM bar_order_items WHERE bar_order_id = p_bar_order_id),
        discount_amount = ROUND((SELECT COALESCE(SUM(line_total), 0) FROM bar_order_items WHERE bar_order_id = p_bar_order_id) * discount_pct / 100, 2),
        total = (SELECT COALESCE(SUM(line_total), 0) FROM bar_order_items WHERE bar_order_id = p_bar_order_id)
              - ROUND((SELECT COALESCE(SUM(line_total), 0) FROM bar_order_items WHERE bar_order_id = p_bar_order_id) * discount_pct / 100, 2)
    WHERE id = p_bar_order_id;

    RETURN v_item_id;
END;
$$;

-- ─── close_bar_tab ───────────────────────────────────────────────────────────
-- Closes a bar tab and records payment.
CREATE OR REPLACE FUNCTION close_bar_tab(
    p_bar_order_id UUID,
    p_payment_method TEXT,
    p_staff_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_order RECORD;
    v_payment_id UUID;
BEGIN
    SELECT * INTO v_order FROM bar_orders WHERE id = p_bar_order_id FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'BAR_ORDER_NOT_FOUND' USING ERRCODE = 'P0001';
    END IF;
    IF v_order.status != 'open' THEN
        RAISE EXCEPTION 'BAR_ORDER_CLOSED' USING ERRCODE = 'P0001';
    END IF;

    -- Close the tab
    UPDATE bar_orders
    SET status = 'closed', closed_at = NOW()
    WHERE id = p_bar_order_id;

    -- Free the table (only if no other open orders on it)
    IF NOT EXISTS (
        SELECT 1 FROM bar_orders
        WHERE table_id = v_order.table_id AND status = 'open' AND id != p_bar_order_id
    ) THEN
        UPDATE bar_tables SET status = 'available' WHERE id = v_order.table_id;
    END IF;

    -- Record payment
    SELECT record_payment('bar', p_bar_order_id, v_order.total, p_payment_method, v_order.member_id, p_staff_id)
    INTO v_payment_id;

    RETURN v_payment_id;
END;
$$;


-- =============================================================================
-- MODULE A FUNCTIONS — Member Management  (Developer 1)
-- =============================================================================

-- ─── register_member ─────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION register_member(
    p_full_name TEXT,
    p_phone TEXT,
    p_email TEXT DEFAULT NULL,
    p_date_of_birth DATE DEFAULT NULL,
    p_plan_id UUID DEFAULT NULL,
    p_client_type TEXT DEFAULT 'individual',
    p_address TEXT DEFAULT NULL,
    p_payment_method TEXT DEFAULT 'cash',
    p_staff_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_member_id UUID;
    v_plan RECORD;
    v_payment_id UUID;
BEGIN
    -- Validate plan
    IF p_plan_id IS NOT NULL THEN
        SELECT * INTO v_plan FROM plans WHERE id = p_plan_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'PLAN_NOT_FOUND' USING ERRCODE = 'P0001';
        END IF;

        -- Junior age check
        IF v_plan.is_junior AND (p_date_of_birth IS NULL OR AGE(CURRENT_DATE, p_date_of_birth) >= INTERVAL '18 years') THEN
            RAISE EXCEPTION 'JUNIOR_AGE_REQUIRED' USING ERRCODE = 'P0001';
        END IF;
    END IF;

    INSERT INTO members (full_name, phone, email, date_of_birth, client_type, plan_id,
                         membership_start, membership_expiry, status, address)
    VALUES (p_full_name, p_phone, p_email, p_date_of_birth, p_client_type, p_plan_id,
            CURRENT_DATE,
            CASE WHEN p_plan_id IS NOT NULL THEN CURRENT_DATE + (v_plan.duration_months || ' months')::INTERVAL ELSE NULL END,
            CASE WHEN p_plan_id IS NOT NULL THEN 'active' ELSE 'active' END,
            p_address)
    RETURNING id INTO v_member_id;

    -- Record membership payment if plan has a price
    IF p_plan_id IS NOT NULL AND v_plan.price > 0 THEN
        SELECT record_payment('membership', v_member_id, v_plan.price, p_payment_method, v_member_id, p_staff_id)
        INTO v_payment_id;
    END IF;

    RETURN v_member_id;
END;
$$;

-- ─── convert_lead ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION convert_lead(
    p_lead_id UUID,
    p_plan_id UUID,
    p_payment_method TEXT DEFAULT 'cash',
    p_staff_id UUID DEFAULT NULL
) RETURNS UUID LANGUAGE plpgsql AS $$
DECLARE
    v_lead RECORD;
    v_member_id UUID;
BEGIN
    SELECT * INTO v_lead FROM leads WHERE id = p_lead_id AND status != 'converted' FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'LEAD_NOT_FOUND_OR_ALREADY_CONVERTED' USING ERRCODE = 'P0001';
    END IF;

    -- Register as member
    SELECT register_member(
        v_lead.full_name, v_lead.phone, v_lead.email,
        NULL, p_plan_id, 'individual', NULL, p_payment_method, p_staff_id
    ) INTO v_member_id;

    -- Update lead
    UPDATE leads
    SET status = 'converted', converted_member_id = v_member_id, updated_at = NOW()
    WHERE id = p_lead_id;

    RETURN v_member_id;
END;
$$;


-- =============================================================================
-- DASHBOARD VIEWS  (Owner: Module D, Developer 4)
-- =============================================================================

-- Revenue by day, source, and method — last 30 days
CREATE OR REPLACE VIEW v_revenue_daily AS
SELECT
    (created_at AT TIME ZONE 'Asia/Kolkata')::DATE AS day,
    source,
    method,
    COUNT(*) AS txn_count,
    SUM(amount) AS total_amount
FROM payments
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY day, source, method
ORDER BY day DESC, source, method;

-- Revenue summary by source
CREATE OR REPLACE VIEW v_revenue_by_source AS
SELECT
    source,
    COUNT(*) AS txn_count,
    SUM(amount) AS total_amount
FROM payments
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY source
ORDER BY total_amount DESC;

-- Low stock products
CREATE OR REPLACE VIEW v_low_stock AS
SELECT
    p.id, p.name, pc.name AS category, p.stock_qty, p.low_stock_threshold
FROM products p
JOIN product_categories pc ON p.category_id = pc.id
WHERE p.is_active = TRUE AND p.stock_qty <= p.low_stock_threshold
ORDER BY p.stock_qty ASC;

-- Member status overview
CREATE OR REPLACE VIEW v_member_status AS
SELECT
    m.id, m.full_name, m.phone, m.email,
    p.name AS plan_name,
    m.membership_expiry,
    CASE
        WHEN m.status = 'suspended' THEN 'suspended'
        WHEN m.membership_expiry < CURRENT_DATE THEN 'expired'
        WHEN m.membership_expiry < CURRENT_DATE + INTERVAL '30 days' THEN 'expiring_soon'
        ELSE 'active'
    END AS computed_status
FROM members m
LEFT JOIN plans p ON m.plan_id = p.id
ORDER BY m.membership_expiry ASC;

-- Today's bar revenue
CREATE OR REPLACE VIEW v_bar_daily AS
SELECT
    (created_at AT TIME ZONE 'Asia/Kolkata')::DATE AS day,
    method,
    COUNT(*) AS txn_count,
    SUM(amount) AS total_amount
FROM payments
WHERE source = 'bar'
GROUP BY day, method
ORDER BY day DESC;

-- Today's court bookings
CREATE OR REPLACE VIEW v_today_bookings AS
SELECT
    b.id AS booking_id,
    c.name AS court_name,
    s.name AS sport_name,
    cs.start_time,
    cs.end_time,
    cs.is_social,
    b.member_id,
    m.full_name AS member_name,
    b.walker_name,
    b.price_charged,
    b.status
FROM bookings b
JOIN court_slots cs ON b.slot_id = cs.id
JOIN courts c ON cs.court_id = c.id
JOIN sports s ON c.sport_id = s.id
LEFT JOIN members m ON b.member_id = m.id
WHERE (cs.start_time AT TIME ZONE 'Asia/Kolkata')::DATE = (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE
ORDER BY cs.start_time;

-- ─── End of schema ───────────────────────────────────────────────────────────
