-- =============================================================================
-- Champions Club — seed.sql
-- Idempotent-friendly: uses ON CONFLICT or checks before inserting.
-- Runnable immediately after schema.sql.
-- References rows by name via subselects, never hardcoded UUIDs.
-- =============================================================================

-- ─── Plans ───────────────────────────────────────────────────────────────────
INSERT INTO plans (name, description, court_rate, shop_discount_pct, bar_discount_pct, daily_booking_limit, duration_months, price, is_junior, trial_rate)
VALUES
    ('Gold',   'Premium full-access membership',      0,    20, 15, 2, 12, 15000, FALSE, 0),
    ('Silver', 'Standard membership',                200,   10, 10, 2, 12,  8000, FALSE, 0),
    ('Junior', 'Under-18 discounted membership',     100,    5,  0, 2,  6,  3000, TRUE,  0)
ON CONFLICT (name) DO NOTHING;

-- ─── Sports ──────────────────────────────────────────────────────────────────
INSERT INTO sports (name) VALUES ('Tennis'), ('Cricket')
ON CONFLICT (name) DO NOTHING;

-- ─── Courts ──────────────────────────────────────────────────────────────────
INSERT INTO courts (name, sport_id, walk_in_rate) VALUES
    ('Tennis Court 1', (SELECT id FROM sports WHERE name = 'Tennis'), 500),
    ('Tennis Court 2', (SELECT id FROM sports WHERE name = 'Tennis'), 500),
    ('Tennis Court 3', (SELECT id FROM sports WHERE name = 'Tennis'), 500),
    ('Cricket Net 1',  (SELECT id FROM sports WHERE name = 'Cricket'), 600),
    ('Cricket Net 2',  (SELECT id FROM sports WHERE name = 'Cricket'), 600)
ON CONFLICT (name) DO NOTHING;

-- ─── Court Slots (next 7 days, 8 AM to 10 PM, every 30 min) ─────────────────
-- Generate slots for each court for the next 7 days
DO $$
DECLARE
    v_court RECORD;
    v_day INT;
    v_slot_start TIMESTAMPTZ;
    v_hour INT;
    v_minute INT;
    v_base_date DATE;
BEGIN
    v_base_date := (NOW() AT TIME ZONE 'Asia/Kolkata')::DATE;

    FOR v_court IN SELECT id FROM courts LOOP
        FOR v_day IN 0..6 LOOP
            FOR v_hour IN 8..21 LOOP
                FOR v_minute IN 0..1 LOOP
                    v_slot_start := ((v_base_date + v_day) || ' ' || 
                                     LPAD(v_hour::TEXT, 2, '0') || ':' || 
                                     LPAD((v_minute * 30)::TEXT, 2, '0') || ':00')::TIMESTAMP 
                                     AT TIME ZONE 'Asia/Kolkata';
                    
                    -- Skip if slot already exists
                    INSERT INTO court_slots (court_id, start_time, end_time, is_social)
                    VALUES (
                        v_court.id,
                        v_slot_start,
                        v_slot_start + INTERVAL '1 hour',
                        -- Mark Friday 7 PM - 10 PM slots as social
                        CASE WHEN EXTRACT(DOW FROM v_slot_start AT TIME ZONE 'Asia/Kolkata') = 5 
                                  AND v_hour >= 19 THEN TRUE ELSE FALSE END
                    )
                    ON CONFLICT (court_id, start_time) DO NOTHING;
                END LOOP;
            END LOOP;
        END LOOP;
    END LOOP;
END;
$$;

-- ─── Members ─────────────────────────────────────────────────────────────────
-- Active Gold member
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type)
VALUES (
    'Rahul Sharma', 'rahul@example.com', '9876543210', '1990-05-15',
    (SELECT id FROM plans WHERE name = 'Gold'),
    CURRENT_DATE - INTERVAL '3 months', CURRENT_DATE + INTERVAL '9 months', 'active', 'individual'
) ON CONFLICT (email) DO NOTHING;

-- Active Silver member
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type)
VALUES (
    'Priya Patel', 'priya@example.com', '9876543211', '1988-11-20',
    (SELECT id FROM plans WHERE name = 'Silver'),
    CURRENT_DATE - INTERVAL '6 months', CURRENT_DATE + INTERVAL '6 months', 'active', 'individual'
) ON CONFLICT (email) DO NOTHING;

-- Expiring soon Silver member
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type)
VALUES (
    'Amit Kumar', 'amit@example.com', '9876543212', '1995-03-10',
    (SELECT id FROM plans WHERE name = 'Silver'),
    CURRENT_DATE - INTERVAL '11 months', CURRENT_DATE + INTERVAL '15 days', 'active', 'individual'
) ON CONFLICT (email) DO NOTHING;

-- Expired member
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type)
VALUES (
    'Deepa Rao', 'deepa@example.com', '9876543213', '1992-07-25',
    (SELECT id FROM plans WHERE name = 'Silver'),
    CURRENT_DATE - INTERVAL '14 months', CURRENT_DATE - INTERVAL '2 months', 'expired', 'individual'
) ON CONFLICT (email) DO NOTHING;

-- Junior member
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type)
VALUES (
    'Arjun Nair', 'arjun@example.com', '9876543214', '2012-09-01',
    (SELECT id FROM plans WHERE name = 'Junior'),
    CURRENT_DATE - INTERVAL '2 months', CURRENT_DATE + INTERVAL '4 months', 'active', 'individual'
) ON CONFLICT (email) DO NOTHING;

-- Business client (Gold)
INSERT INTO members (full_name, email, phone, plan_id, membership_start, membership_expiry, status, client_type)
VALUES (
    'TechCorp Pvt Ltd', 'accounts@techcorp.com', '9876543215',
    (SELECT id FROM plans WHERE name = 'Gold'),
    CURRENT_DATE - INTERVAL '1 month', CURRENT_DATE + INTERVAL '11 months', 'active', 'business'
) ON CONFLICT (email) DO NOTHING;

-- ─── Product Categories ──────────────────────────────────────────────────────
INSERT INTO product_categories (name) VALUES
    ('Rackets'), ('Balls'), ('Shoes'), ('Accessories'), ('Apparel')
ON CONFLICT (name) DO NOTHING;

-- ─── Products ────────────────────────────────────────────────────────────────
INSERT INTO products (category_id, name, description, price, stock_qty, low_stock_threshold) VALUES
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Pro Staff 97',       'Wilson Pro Staff 97 v14',  18999, 8,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Pure Aero',          'Babolat Pure Aero 2024',   16999, 5,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Clash 100',          'Wilson Clash 100 v2',      15499, 6,  3),
    ((SELECT id FROM product_categories WHERE name = 'Balls'),   'Championship Balls',  'Wilson Championship 3-pack', 499, 45, 10),
    ((SELECT id FROM product_categories WHERE name = 'Balls'),   'Pro Penn Balls',      'Penn Pro Marathon 3-pack',   599, 30, 10),
    ((SELECT id FROM product_categories WHERE name = 'Balls'),   'Cricket Ball Red',    'SG Test red leather ball',   849,  2,  5), -- LOW STOCK!
    ((SELECT id FROM product_categories WHERE name = 'Shoes'),   'Air Zoom Vapor 11',   'Nike Court Air Zoom Vapor',12999, 10,  3),
    ((SELECT id FROM product_categories WHERE name = 'Shoes'),   'Gel Resolution 9',    'Asics Gel Resolution 9',   10999, 7,  3),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Pro Overgrip 3pk', 'Wilson Pro Overgrip',        349, 25,  5),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Dampener Pack',    'Babolat Custom Damp 2pk',    249, 20,  5),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Cricket Gloves',   'SG Test batting gloves',    2499,  4,  3),
    ((SELECT id FROM product_categories WHERE name = 'Apparel'),    'Dri-FIT Polo',      'Nike Court Dri-FIT polo',   3499, 12,  3),
    ((SELECT id FROM product_categories WHERE name = 'Apparel'),    'Club Cap',           'Champions Club cap',         799, 20,  5);

-- ─── Bar Menu Categories ─────────────────────────────────────────────────────
INSERT INTO bar_menu_categories (name) VALUES
    ('Beverages'), ('Starters'), ('Mains'), ('Desserts')
ON CONFLICT (name) DO NOTHING;

-- ─── Bar Menu Items ──────────────────────────────────────────────────────────
INSERT INTO bar_menu_items (category_id, name, description, price) VALUES
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Fresh Lime Soda',    'Sweet or salted',            99),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Cold Coffee',        'Iced coffee with cream',    149),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Mango Lassi',        'Thick mango yogurt drink',  129),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Mineral Water',      '500ml bottle',               49),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Energy Drink',       'Electrolyte sports drink',  159),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'),  'Paneer Tikka',       '6 pcs with mint chutney',   349),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'),  'Chicken Wings',      'BBQ sauce, 8 pcs',          449),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'),  'French Fries',       'Crispy with ketchup',       199),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'),  'Veg Spring Rolls',   '4 pcs with sweet chili',    249),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'),     'Club Sandwich',      'Triple-decker, grilled',    349),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'),     'Butter Chicken',     'With naan bread',           449),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'),     'Veg Biryani',        'Hyderabadi style',          349),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'),     'Grilled Chicken',    'With salad and fries',      499),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Desserts'),  'Gulab Jamun',        '2 pcs, warm',               149),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Desserts'),  'Ice Cream Sundae',   'Chocolate or vanilla',      199);

-- ─── Bar Tables ──────────────────────────────────────────────────────────────
INSERT INTO bar_tables (table_number, seats, status) VALUES
    (1, 4, 'available'), (2, 4, 'available'), (3, 6, 'available'),
    (4, 6, 'available'), (5, 2, 'available'), (6, 2, 'available'),
    (7, 8, 'available'), (8, 4, 'available')
ON CONFLICT (table_number) DO NOTHING;

-- ─── Staff ───────────────────────────────────────────────────────────────────
INSERT INTO staff (full_name, email, phone, role, monthly_salary, leave_balance) VALUES
    ('Vikram Singh',    'vikram@champions.club',  '9800000001', 'owner',        100000, 0),
    ('Meera Bhat',      'meera@champions.club',   '9800000008', 'manager',       45000, 15),
    ('Sneha Desai',     'sneha@champions.club',   '9800000002', 'front_desk',    25000, 12),
    ('Rajesh Menon',    'rajesh@champions.club',  '9800000003', 'front_desk',    25000, 12),
    ('Pooja Iyer',      'pooja@champions.club',   '9800000004', 'bar_staff',     22000, 12),
    ('Karan Joshi',     'karan@champions.club',   '9800000005', 'bar_staff',     22000, 12),
    ('Anita Das',       'anita@champions.club',   '9800000006', 'kitchen_staff', 20000, 12),
    ('Suresh Reddy',    'suresh@champions.club',  '9800000007', 'shop_staff',    22000, 12),
    ('Admin User',      'admin@champions.club',   '9800000000', 'admin',         30000, 15)
ON CONFLICT (email) DO NOTHING;

-- ─── Shifts (this week) ─────────────────────────────────────────────────────
DO $$
DECLARE
    v_day INT;
    v_date DATE;
BEGIN
    FOR v_day IN 0..6 LOOP
        v_date := CURRENT_DATE + v_day;
        -- Front desk: morning + evening shift
        INSERT INTO shifts (staff_id, shift_date, start_time, end_time, notes)
        VALUES
            ((SELECT id FROM staff WHERE email = 'sneha@champions.club'), v_date, '08:00', '14:00', 'Morning shift'),
            ((SELECT id FROM staff WHERE email = 'rajesh@champions.club'), v_date, '14:00', '22:00', 'Evening shift'),
            ((SELECT id FROM staff WHERE email = 'pooja@champions.club'), v_date, '11:00', '19:00', 'Day shift'),
            ((SELECT id FROM staff WHERE email = 'karan@champions.club'), v_date, '15:00', '23:00', 'Evening shift'),
            ((SELECT id FROM staff WHERE email = 'anita@champions.club'), v_date, '10:00', '18:00', 'Kitchen shift'),
            ((SELECT id FROM staff WHERE email = 'suresh@champions.club'), v_date, '09:00', '17:00', 'Shop shift');
    END LOOP;
END;
$$;

-- ─── A Pending Lead ──────────────────────────────────────────────────────────
INSERT INTO leads (full_name, email, phone, message, source, status, assigned_staff_id)
VALUES (
    'Neha Kapoor', 'neha.k@gmail.com', '9811223344',
    'Hi, I found your club online. I am interested in joining with my husband. Do you have a couples plan or can we both get Gold? Also, do you offer trial sessions?',
    'website', 'new',
    (SELECT id FROM staff WHERE email = 'sneha@champions.club')
);

INSERT INTO leads (full_name, phone, message, source, status)
VALUES (
    'Ravi Gupta', '9822334455',
    'Called asking about cricket net availability on weekends.',
    'phone', 'contacted'
);

-- ─── Leave Request ───────────────────────────────────────────────────────────
INSERT INTO leave_requests (staff_id, start_date, end_date, reason, status)
VALUES (
    (SELECT id FROM staff WHERE email = 'pooja@champions.club'),
    CURRENT_DATE + INTERVAL '5 days',
    CURRENT_DATE + INTERVAL '7 days',
    'Family function',
    'pending'
);

-- =============================================================================
-- ~150 RANDOMIZED PAST PAYMENTS (last 30 days)
-- Spread across courts, shop, bar, and membership sources
-- =============================================================================
DO $$
DECLARE
    v_i INT;
    v_source TEXT;
    v_method TEXT;
    v_amount NUMERIC(10,2);
    v_member_id UUID;
    v_day_offset INT;
    v_sources TEXT[] := ARRAY['court', 'shop', 'bar', 'membership'];
    v_methods TEXT[] := ARRAY['cash', 'card', 'upi'];
    v_members UUID[];
    v_ref_id UUID;
BEGIN
    -- Collect member IDs
    SELECT ARRAY_AGG(id) INTO v_members FROM members WHERE status = 'active';

    FOR v_i IN 1..150 LOOP
        -- Random source (weighted: courts 35%, shop 25%, bar 35%, membership 5%)
        CASE
            WHEN v_i <= 52 THEN v_source := 'court';
            WHEN v_i <= 90 THEN v_source := 'bar';
            WHEN v_i <= 127 THEN v_source := 'shop';
            ELSE v_source := 'membership';
        END CASE;

        -- Random payment method
        v_method := v_methods[1 + floor(random() * 3)::INT];

        -- Random amount based on source
        CASE v_source
            WHEN 'court' THEN v_amount := (ARRAY[0, 200, 500, 600])[1 + floor(random() * 4)::INT];
            WHEN 'shop' THEN v_amount := (ARRAY[249, 349, 499, 799, 2499, 10999, 15499, 16999])[1 + floor(random() * 8)::INT];
            WHEN 'bar' THEN v_amount := 100 + floor(random() * 1500)::INT;
            WHEN 'membership' THEN v_amount := (ARRAY[3000, 8000, 15000])[1 + floor(random() * 3)::INT];
        END CASE;

        -- Random member (sometimes NULL for walk-ins)
        IF random() > 0.3 AND v_members IS NOT NULL AND array_length(v_members, 1) > 0 THEN
            v_member_id := v_members[1 + floor(random() * array_length(v_members, 1))::INT];
        ELSE
            v_member_id := NULL;
        END IF;

        -- Random day in last 30 days
        v_day_offset := floor(random() * 30)::INT;
        v_ref_id := gen_random_uuid(); -- dummy reference for seed data

        INSERT INTO payments (source, reference_id, amount, method, member_id, created_at)
        VALUES (v_source, v_ref_id, v_amount, v_method, v_member_id,
                NOW() - (v_day_offset || ' days')::INTERVAL
                      - (floor(random() * 12) || ' hours')::INTERVAL);
    END LOOP;
END;
$$;

-- ─── End of seed ─────────────────────────────────────────────────────────────
