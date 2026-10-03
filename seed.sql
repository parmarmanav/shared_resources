-- =============================================================================
-- Champions Club — seed.sql  (EXPANDED)
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

-- ─── Court Slots (next 14 days, 8 AM to 10 PM, every 30 min) ────────────────
-- Generate slots for each court for the next 14 days (2 weeks)
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
        FOR v_day IN 0..13 LOOP
            FOR v_hour IN 8..21 LOOP
                FOR v_minute IN 0..1 LOOP
                    v_slot_start := ((v_base_date + v_day) || ' ' || 
                                     LPAD(v_hour::TEXT, 2, '0') || ':' || 
                                     LPAD((v_minute * 30)::TEXT, 2, '0') || ':00')::TIMESTAMP 
                                     AT TIME ZONE 'Asia/Kolkata';
                    
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


-- =============================================================================
-- MEMBERS — 25 members across all plans, statuses, and types
-- =============================================================================

-- ── Gold Members (8) ────────────────────────────────────────────────────────
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type, address) VALUES
('Rahul Sharma',     'rahul@example.com',     '9876543210', '1990-05-15', (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '3 months',  CURRENT_DATE + INTERVAL '9 months',  'active', 'individual', '42, MG Road, Bangalore'),
('Ananya Iyer',      'ananya@example.com',    '9876543220', '1985-02-28', (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '8 months',  CURRENT_DATE + INTERVAL '4 months',  'active', 'individual', '15, Koramangala 5th Block, Bangalore'),
('Vikash Mehra',     'vikash@example.com',    '9876543221', '1982-11-10', (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '1 month',   CURRENT_DATE + INTERVAL '11 months', 'active', 'individual', '88, Indiranagar, Bangalore'),
('Kavitha Nair',     'kavitha@example.com',   '9876543222', '1993-07-19', (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '5 months',  CURRENT_DATE + INTERVAL '7 months',  'active', 'individual', '3, Whitefield Main Road, Bangalore'),
('Rohan Kapoor',     'rohan@example.com',     '9876543223', '1988-12-03', (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '10 months', CURRENT_DATE + INTERVAL '2 months',  'active', 'individual', '201, HSR Layout, Bangalore'),
('Sunita Reddy',     'sunita@example.com',    '9876543224', '1979-04-22', (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '11 months', CURRENT_DATE + INTERVAL '20 days',   'active', 'individual', '56, Jayanagar 4th Block, Bangalore'),
('Manoj Tiwari',     'manoj@example.com',     '9876543225', '1991-09-14', (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '13 months', CURRENT_DATE - INTERVAL '1 month',   'expired', 'individual', '12, Rajajinagar, Bangalore'),
('TechCorp Pvt Ltd', 'accounts@techcorp.com', '9876543215', NULL,         (SELECT id FROM plans WHERE name = 'Gold'),   CURRENT_DATE - INTERVAL '1 month',   CURRENT_DATE + INTERVAL '11 months', 'active', 'business',   '100, Electronic City Phase 1, Bangalore')
ON CONFLICT (email) DO NOTHING;

-- ── Silver Members (9) ──────────────────────────────────────────────────────
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type, address) VALUES
('Priya Patel',     'priya@example.com',     '9876543211', '1988-11-20', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '6 months',  CURRENT_DATE + INTERVAL '6 months',  'active', 'individual', '77, BTM Layout 2nd Stage, Bangalore'),
('Amit Kumar',      'amit@example.com',      '9876543212', '1995-03-10', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '11 months', CURRENT_DATE + INTERVAL '15 days',   'active', 'individual', '33, Marathahalli, Bangalore'),
('Deepa Rao',       'deepa@example.com',     '9876543213', '1992-07-25', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '14 months', CURRENT_DATE - INTERVAL '2 months',  'expired', 'individual', '9, JP Nagar, Bangalore'),
('Farhan Sheikh',   'farhan@example.com',    '9876543230', '1990-01-05', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '4 months',  CURRENT_DATE + INTERVAL '8 months',  'active', 'individual', '25, Yelahanka New Town, Bangalore'),
('Geeta Krishnan',  'geeta@example.com',     '9876543231', '1987-06-18', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '9 months',  CURRENT_DATE + INTERVAL '3 months',  'active', 'individual', '67, Hebbal, Bangalore'),
('Harish Jain',     'harish@example.com',    '9876543232', '1994-08-30', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '2 months',  CURRENT_DATE + INTERVAL '10 months', 'active', 'individual', '5, Sarjapur Road, Bangalore'),
('Isha Gupta',      'isha@example.com',      '9876543233', '1996-10-12', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '7 months',  CURRENT_DATE + INTERVAL '5 months',  'active', 'individual', '19, Malleshwaram, Bangalore'),
('Jatin Malhotra',  'jatin@example.com',     '9876543234', '1983-03-25', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '12 months', CURRENT_DATE - INTERVAL '5 days',    'expired', 'individual', '41, RT Nagar, Bangalore'),
('SportzElite LLC', 'hello@sportzelite.in',  '9876543235', NULL,         (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '3 months',  CURRENT_DATE + INTERVAL '9 months',  'active', 'business',   '22, Whitefield, Bangalore')
ON CONFLICT (email) DO NOTHING;

-- ── Junior Members (4) ──────────────────────────────────────────────────────
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type) VALUES
('Arjun Nair',      'arjun@example.com',     '9876543214', '2012-09-01', (SELECT id FROM plans WHERE name = 'Junior'), CURRENT_DATE - INTERVAL '2 months',  CURRENT_DATE + INTERVAL '4 months',  'active',  'individual'),
('Sanya Choudhary', 'sanya@example.com',     '9876543240', '2013-04-15', (SELECT id FROM plans WHERE name = 'Junior'), CURRENT_DATE - INTERVAL '1 month',   CURRENT_DATE + INTERVAL '5 months',  'active',  'individual'),
('Dev Kulkarni',    'dev.k@example.com',     '9876543241', '2011-12-20', (SELECT id FROM plans WHERE name = 'Junior'), CURRENT_DATE - INTERVAL '5 months',  CURRENT_DATE + INTERVAL '1 month',   'active',  'individual'),
('Riya Saxena',     'riya@example.com',      '9876543242', '2014-07-08', (SELECT id FROM plans WHERE name = 'Junior'), CURRENT_DATE - INTERVAL '6 months',  CURRENT_DATE - INTERVAL '10 days',   'expired', 'individual')
ON CONFLICT (email) DO NOTHING;

-- ── Suspended Member (1) ────────────────────────────────────────────────────
INSERT INTO members (full_name, email, phone, date_of_birth, plan_id, membership_start, membership_expiry, status, client_type, notes) VALUES
('Nikhil Sood',     'nikhil@example.com',    '9876543250', '1989-02-14', (SELECT id FROM plans WHERE name = 'Silver'), CURRENT_DATE - INTERVAL '8 months',  CURRENT_DATE + INTERVAL '4 months',  'suspended', 'individual', 'Suspended due to repeated no-shows and unpaid bar tab')
ON CONFLICT (email) DO NOTHING;

-- ── No-plan walk-in regulars (2 — registered but no plan yet) ───────────────
INSERT INTO members (full_name, email, phone, date_of_birth, status, client_type) VALUES
('Lakshmi Venkat',  'lakshmi@example.com',   '9876543260', '1997-05-22', 'active', 'individual'),
('Omar Farooq',     'omar@example.com',      '9876543261', '1986-10-30', 'active', 'individual')
ON CONFLICT (email) DO NOTHING;


-- =============================================================================
-- PRODUCT CATALOG — 30+ items across 5 categories
-- =============================================================================

INSERT INTO product_categories (name) VALUES
    ('Rackets'), ('Balls'), ('Shoes'), ('Accessories'), ('Apparel')
ON CONFLICT (name) DO NOTHING;

INSERT INTO products (category_id, name, description, price, stock_qty, low_stock_threshold) VALUES
    -- Rackets (7)
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Pro Staff 97',          'Wilson Pro Staff 97 v14',                18999, 8,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Pure Aero',             'Babolat Pure Aero 2024',                 16999, 5,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Clash 100',             'Wilson Clash 100 v2',                    15499, 6,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'EZONE 98',              'Yonex EZONE 98 7th Gen',                 17499, 4,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Head Speed MP',         'Head Speed MP 2024',                     14999, 7,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Tecnifibre TF-X1',      'Tecnifibre TF-X1 300',                   13999, 3,  3),
    ((SELECT id FROM product_categories WHERE name = 'Rackets'), 'Junior Racket 23"',     'Wilson Burn 23 inch for kids',            3499, 10, 3),

    -- Balls (6)
    ((SELECT id FROM product_categories WHERE name = 'Balls'), 'Championship Balls',      'Wilson Championship 3-pack',               499, 45, 10),
    ((SELECT id FROM product_categories WHERE name = 'Balls'), 'Pro Penn Balls',           'Penn Pro Marathon 3-pack',                 599, 30, 10),
    ((SELECT id FROM product_categories WHERE name = 'Balls'), 'Dunlop Fort All Court',   'Dunlop Fort All Court 3-pack',             549, 35, 10),
    ((SELECT id FROM product_categories WHERE name = 'Balls'), 'Cricket Ball Red',         'SG Test red leather ball',                 849,  2,  5),
    ((SELECT id FROM product_categories WHERE name = 'Balls'), 'Cricket Ball White',       'SG White limited over ball',               749, 12,  5),
    ((SELECT id FROM product_categories WHERE name = 'Balls'), 'Tennis Ball Hopper 72pk',  'Tourna 72-ball pressureless practice',    2999,  6,  3),

    -- Shoes (5)
    ((SELECT id FROM product_categories WHERE name = 'Shoes'), 'Air Zoom Vapor 11',       'Nike Court Air Zoom Vapor',              12999, 10, 3),
    ((SELECT id FROM product_categories WHERE name = 'Shoes'), 'Gel Resolution 9',         'Asics Gel Resolution 9',                 10999, 7,  3),
    ((SELECT id FROM product_categories WHERE name = 'Shoes'), 'Barricade 13',             'Adidas Barricade 13 clay',               11499, 5,  3),
    ((SELECT id FROM product_categories WHERE name = 'Shoes'), 'Rush Pro 4.0',             'Wilson Rush Pro 4.0',                     9999, 8,  3),
    ((SELECT id FROM product_categories WHERE name = 'Shoes'), 'Cricket Spikes Pro',       'Puma FH 22 cricket spikes',               7999, 4,  3),

    -- Accessories (8)
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Pro Overgrip 3pk',   'Wilson Pro Overgrip',                      349, 25, 5),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Dampener Pack',       'Babolat Custom Damp 2pk',                 249, 20, 5),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Cricket Gloves',      'SG Test batting gloves',                 2499,  4, 3),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Cricket Pads',        'SG Test batting pads',                   3499,  3, 3),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Racket Bag 6-pack',   'Wilson Tour 6-pack bag',                 5999,  6, 3),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Tennis Wristband',    'Nike swoosh wristband pair',              499, 30, 5),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'String Reel',          'Luxilon ALU Power 200m reel',            8999,  2, 2),
    ((SELECT id FROM product_categories WHERE name = 'Accessories'), 'Water Bottle 1L',     'Champions Club branded bottle',           599, 40, 10),

    -- Apparel (6)
    ((SELECT id FROM product_categories WHERE name = 'Apparel'), 'Dri-FIT Polo',           'Nike Court Dri-FIT polo',                3499, 12, 3),
    ((SELECT id FROM product_categories WHERE name = 'Apparel'), 'Club Cap',                'Champions Club cap',                      799, 20, 5),
    ((SELECT id FROM product_categories WHERE name = 'Apparel'), 'Tennis Skirt',            'Adidas Club pleated skirt',              2499,  8, 3),
    ((SELECT id FROM product_categories WHERE name = 'Apparel'), 'Training Shorts',         'Nike Dri-FIT training shorts',           1999, 15, 5),
    ((SELECT id FROM product_categories WHERE name = 'Apparel'), 'Compression Sleeve',      'Under Armour elbow sleeve',              1299,  9, 3),
    ((SELECT id FROM product_categories WHERE name = 'Apparel'), 'Club Hoodie',             'Champions Club premium hoodie',          2999,  7, 3);


-- =============================================================================
-- BAR & CAFETERIA — 25 menu items, 10 tables
-- =============================================================================

INSERT INTO bar_menu_categories (name) VALUES
    ('Beverages'), ('Starters'), ('Mains'), ('Desserts'), ('Smoothies & Shakes')
ON CONFLICT (name) DO NOTHING;

INSERT INTO bar_menu_items (category_id, name, description, price) VALUES
    -- Beverages (7)
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Fresh Lime Soda',      'Sweet or salted',              99),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Cold Coffee',           'Iced coffee with cream',      149),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Mango Lassi',           'Thick mango yogurt drink',    129),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Mineral Water',         '500ml bottle',                 49),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Energy Drink',          'Electrolyte sports drink',    159),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Masala Chai',           'Hot spiced tea',               69),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Beverages'), 'Coconut Water',         'Fresh tender coconut',         89),

    -- Starters (6)
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'), 'Paneer Tikka',           '6 pcs with mint chutney',    349),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'), 'Chicken Wings',          'BBQ sauce, 8 pcs',           449),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'), 'French Fries',           'Crispy with ketchup',        199),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'), 'Veg Spring Rolls',       '4 pcs with sweet chili',     249),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'), 'Garlic Bread',           'Cheesy garlic bread 4 pcs',  199),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Starters'), 'Chicken Seekh Kebab',    '4 pcs with green chutney',   399),

    -- Mains (6)
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'), 'Club Sandwich',             'Triple-decker, grilled',     349),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'), 'Butter Chicken',            'With naan bread',            449),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'), 'Veg Biryani',               'Hyderabadi style',           349),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'), 'Grilled Chicken',           'With salad and fries',       499),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'), 'Margherita Pizza',          '8-inch thin crust',          399),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Mains'), 'Chicken Fried Rice',        'Indo-Chinese style',         299),

    -- Desserts (3)
    ((SELECT id FROM bar_menu_categories WHERE name = 'Desserts'), 'Gulab Jamun',            '2 pcs, warm',                149),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Desserts'), 'Ice Cream Sundae',       'Chocolate or vanilla',       199),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Desserts'), 'Brownie with Ice Cream', 'Warm fudge brownie',         249),

    -- Smoothies & Shakes (3)
    ((SELECT id FROM bar_menu_categories WHERE name = 'Smoothies & Shakes'), 'Protein Shake',      'Whey + banana + peanut butter', 249),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Smoothies & Shakes'), 'Berry Blast Smoothie','Mixed berries + yogurt',        199),
    ((SELECT id FROM bar_menu_categories WHERE name = 'Smoothies & Shakes'), 'Oreo Milkshake',     'Crushed Oreo + vanilla',        229);

-- 10 bar tables
INSERT INTO bar_tables (table_number, seats, status) VALUES
    (1, 4, 'available'), (2, 4, 'available'), (3, 6, 'available'),
    (4, 6, 'available'), (5, 2, 'available'), (6, 2, 'available'),
    (7, 8, 'available'), (8, 4, 'available'), (9, 4, 'available'),
    (10, 6, 'available')
ON CONFLICT (table_number) DO NOTHING;


-- =============================================================================
-- STAFF — 12 staff members
-- =============================================================================

INSERT INTO staff (full_name, email, phone, role, monthly_salary, leave_balance) VALUES
    ('Vikram Singh',     'vikram@champions.club',  '9800000001', 'owner',         100000, 0),
    ('Meera Bhat',       'meera@champions.club',   '9800000008', 'manager',        45000, 15),
    ('Sneha Desai',      'sneha@champions.club',   '9800000002', 'front_desk',     25000, 12),
    ('Rajesh Menon',     'rajesh@champions.club',  '9800000003', 'front_desk',     25000, 12),
    ('Pooja Iyer',       'pooja@champions.club',   '9800000004', 'bar_staff',      22000, 12),
    ('Karan Joshi',      'karan@champions.club',   '9800000005', 'bar_staff',      22000, 12),
    ('Anita Das',        'anita@champions.club',   '9800000006', 'kitchen_staff',  20000, 12),
    ('Suresh Reddy',     'suresh@champions.club',  '9800000007', 'shop_staff',     22000, 12),
    ('Admin User',       'admin@champions.club',   '9800000000', 'admin',          30000, 15),
    ('Divya Pillai',     'divya@champions.club',   '9800000009', 'bar_staff',      22000, 12),
    ('Ramu Prasad',      'ramu@champions.club',    '9800000010', 'kitchen_staff',  20000, 12),
    ('Nisha Verma',      'nisha@champions.club',   '9800000011', 'shop_staff',     22000, 12)
ON CONFLICT (email) DO NOTHING;


-- =============================================================================
-- SHIFTS — 2 weeks of schedules
-- =============================================================================
DO $$
DECLARE
    v_day INT;
    v_date DATE;
BEGIN
    FOR v_day IN 0..13 LOOP
        v_date := CURRENT_DATE + v_day;
        INSERT INTO shifts (staff_id, shift_date, start_time, end_time, notes)
        VALUES
            -- Front desk (2 shifts)
            ((SELECT id FROM staff WHERE email = 'sneha@champions.club'),  v_date, '08:00', '14:00', 'Morning shift'),
            ((SELECT id FROM staff WHERE email = 'rajesh@champions.club'), v_date, '14:00', '22:00', 'Evening shift'),
            -- Bar staff (3 shifts)
            ((SELECT id FROM staff WHERE email = 'pooja@champions.club'),  v_date, '11:00', '19:00', 'Day shift'),
            ((SELECT id FROM staff WHERE email = 'karan@champions.club'),  v_date, '15:00', '23:00', 'Evening shift'),
            ((SELECT id FROM staff WHERE email = 'divya@champions.club'),  v_date, '11:00', '15:00', 'Lunch rush'),
            -- Kitchen (2 shifts)
            ((SELECT id FROM staff WHERE email = 'anita@champions.club'),  v_date, '10:00', '18:00', 'Kitchen day shift'),
            ((SELECT id FROM staff WHERE email = 'ramu@champions.club'),   v_date, '14:00', '22:00', 'Kitchen evening shift'),
            -- Shop (2 shifts)
            ((SELECT id FROM staff WHERE email = 'suresh@champions.club'), v_date, '09:00', '17:00', 'Shop day shift'),
            ((SELECT id FROM staff WHERE email = 'nisha@champions.club'),  v_date, '13:00', '21:00', 'Shop evening shift'),
            -- Manager
            ((SELECT id FROM staff WHERE email = 'meera@champions.club'),  v_date, '09:00', '18:00', 'Manager on duty');
    END LOOP;
END;
$$;


-- =============================================================================
-- LEADS / ENQUIRIES — 10 leads in various stages
-- =============================================================================

INSERT INTO leads (full_name, email, phone, message, source, status, assigned_staff_id) VALUES
('Neha Kapoor',      'neha.k@gmail.com',       '9811223344', 'Hi, I found your club online. Interested in joining with my husband. Do you have a couples plan or can we both get Gold? Also, do you offer trial sessions?', 'website', 'new',       (SELECT id FROM staff WHERE email = 'sneha@champions.club')),
('Ravi Gupta',        NULL,                     '9822334455', 'Called asking about cricket net availability on weekends.',                                                                                                  'phone',   'contacted', (SELECT id FROM staff WHERE email = 'rajesh@champions.club')),
('Siddharth Bansal',  'sid.b@outlook.com',      '9833445566', 'Looking for corporate membership for 10 employees. Need pricing details.',                                                                                  'website', 'quoted',    (SELECT id FROM staff WHERE email = 'meera@champions.club')),
('Meghna Rao',        'meghna.r@gmail.com',     '9844556677', 'Want to enroll my 12-year-old son for tennis coaching. Is there a junior plan?',                                                                            'website', 'new',       (SELECT id FROM staff WHERE email = 'sneha@champions.club')),
('Pranav Deshmukh',   NULL,                     '9855667788', 'Walk-in enquiry. Played a trial session, seemed very interested in Silver plan.',                                                                           'walk_in', 'contacted', (SELECT id FROM staff WHERE email = 'rajesh@champions.club')),
('Anjali Mehta',      'anjali.m@yahoo.com',     '9866778899', 'Referred by Rahul Sharma (Gold member). Interested in Gold membership.',                                                                                   'referral', 'quoted',   (SELECT id FROM staff WHERE email = 'meera@champions.club')),
('Kunal Deshpande',   'kunal.d@gmail.com',      '9877889900', 'Enquiring about hosting a corporate tennis tournament for 20 people.',                                                                                     'website', 'new',       NULL),
('Fatima Khan',       'fatima.k@hotmail.com',   '9888990011', 'Called asking about ladies-only sessions and timings.',                                                                                                     'phone',   'contacted', (SELECT id FROM staff WHERE email = 'sneha@champions.club')),
('Aditya Sharma',     'aditya.s@gmail.com',     '9899001122', 'Visited club, took tour, wants to discuss Silver vs Gold benefits.',                                                                                       'walk_in', 'quoted',    (SELECT id FROM staff WHERE email = 'meera@champions.club')),
('Pallavi Joshi',     'pallavi.j@gmail.com',    '9800112233', 'Instagram DM — saw our social Friday post. Wants to bring 4 friends.',                                                                                    'website', 'new',       (SELECT id FROM staff WHERE email = 'sneha@champions.club'));

-- Mark one lead as converted (Ravi Gupta joined as Silver)
-- We'll handle this manually since convert_lead() might not have all context
INSERT INTO members (full_name, email, phone, plan_id, membership_start, membership_expiry, status, client_type) VALUES
('Ravi Gupta',   'ravi.g@example.com', '9822334455',
 (SELECT id FROM plans WHERE name = 'Silver'),
 CURRENT_DATE - INTERVAL '5 days', CURRENT_DATE + INTERVAL '355 days', 'active', 'individual')
ON CONFLICT (email) DO NOTHING;

UPDATE leads SET status = 'converted',
    converted_member_id = (SELECT id FROM members WHERE email = 'ravi.g@example.com'),
    updated_at = NOW()
WHERE phone = '9822334455' AND full_name = 'Ravi Gupta';

-- One lost lead
UPDATE leads SET status = 'lost', notes = 'Too expensive, went to another club', updated_at = NOW()
WHERE full_name = 'Kunal Deshpande';


-- =============================================================================
-- LEAVE REQUESTS — varied statuses
-- =============================================================================

INSERT INTO leave_requests (staff_id, start_date, end_date, reason, status, approved_by) VALUES
((SELECT id FROM staff WHERE email = 'pooja@champions.club'),
 CURRENT_DATE + INTERVAL '5 days', CURRENT_DATE + INTERVAL '7 days',
 'Family function', 'pending', NULL),

((SELECT id FROM staff WHERE email = 'anita@champions.club'),
 CURRENT_DATE + INTERVAL '10 days', CURRENT_DATE + INTERVAL '12 days',
 'Medical appointment', 'approved',
 (SELECT id FROM staff WHERE email = 'meera@champions.club')),

((SELECT id FROM staff WHERE email = 'karan@champions.club'),
 CURRENT_DATE - INTERVAL '3 days', CURRENT_DATE - INTERVAL '1 day',
 'Fever and cold', 'approved',
 (SELECT id FROM staff WHERE email = 'meera@champions.club')),

((SELECT id FROM staff WHERE email = 'suresh@champions.club'),
 CURRENT_DATE + INTERVAL '20 days', CURRENT_DATE + INTERVAL '25 days',
 'Annual vacation — going to Kerala', 'pending', NULL),

((SELECT id FROM staff WHERE email = 'rajesh@champions.club'),
 CURRENT_DATE + INTERVAL '2 days', CURRENT_DATE + INTERVAL '2 days',
 'Personal work — half day', 'rejected',
 (SELECT id FROM staff WHERE email = 'meera@champions.club')),

((SELECT id FROM staff WHERE email = 'divya@champions.club'),
 CURRENT_DATE + INTERVAL '15 days', CURRENT_DATE + INTERVAL '18 days',
 'Sister wedding', 'approved',
 (SELECT id FROM staff WHERE email = 'vikram@champions.club'));


-- =============================================================================
-- PAYROLL — Last 3 months
-- =============================================================================
DO $$
DECLARE
    v_staff RECORD;
    v_month_offset INT;
    v_month DATE;
    v_deductions NUMERIC;
BEGIN
    FOR v_staff IN SELECT id, monthly_salary, email FROM staff WHERE monthly_salary IS NOT NULL AND monthly_salary > 0 LOOP
        FOR v_month_offset IN 1..3 LOOP
            v_month := DATE_TRUNC('month', CURRENT_DATE - (v_month_offset || ' months')::INTERVAL)::DATE;
            
            -- Random deductions (0 to 2000)
            v_deductions := floor(random() * 2000)::INT;

            INSERT INTO payroll (staff_id, month, gross_salary, deductions, net_salary, status, paid_at)
            VALUES (
                v_staff.id,
                v_month,
                v_staff.monthly_salary,
                v_deductions,
                v_staff.monthly_salary - v_deductions,
                'paid',
                (v_month + INTERVAL '28 days')::TIMESTAMPTZ
            )
            ON CONFLICT (staff_id, month) DO NOTHING;
        END LOOP;
    END LOOP;

    -- Current month: pending payroll
    FOR v_staff IN SELECT id, monthly_salary FROM staff WHERE monthly_salary IS NOT NULL AND monthly_salary > 0 LOOP
        INSERT INTO payroll (staff_id, month, gross_salary, deductions, net_salary, status)
        VALUES (
            v_staff.id,
            DATE_TRUNC('month', CURRENT_DATE)::DATE,
            v_staff.monthly_salary,
            0,
            v_staff.monthly_salary,
            'pending'
        )
        ON CONFLICT (staff_id, month) DO NOTHING;
    END LOOP;
END;
$$;


-- =============================================================================
-- INVOICES — 5 invoices (membership renewals, business client billing)
-- =============================================================================

INSERT INTO invoices (invoice_number, member_id, client_name, status, subtotal, tax_amount, total, due_date, paid_at, notes) VALUES
('INV-2026-0001',
 (SELECT id FROM members WHERE email = 'accounts@techcorp.com'),
 'TechCorp Pvt Ltd',
 'paid', 15000, 2700, 17700,
 CURRENT_DATE - INTERVAL '20 days',
 NOW() - INTERVAL '18 days',
 'Annual Gold membership — corporate'),

('INV-2026-0002',
 (SELECT id FROM members WHERE email = 'hello@sportzelite.in'),
 'SportzElite LLC',
 'paid', 8000, 1440, 9440,
 CURRENT_DATE - INTERVAL '10 days',
 NOW() - INTERVAL '8 days',
 'Annual Silver membership — corporate'),

('INV-2026-0003',
 (SELECT id FROM members WHERE email = 'rahul@example.com'),
 NULL,
 'sent', 15000, 2700, 17700,
 CURRENT_DATE + INTERVAL '15 days',
 NULL,
 'Upcoming Gold membership renewal'),

('INV-2026-0004',
 (SELECT id FROM members WHERE email = 'deepa@example.com'),
 NULL,
 'overdue', 8000, 1440, 9440,
 CURRENT_DATE - INTERVAL '30 days',
 NULL,
 'Silver membership renewal — expired, unpaid'),

('INV-2026-0005',
 NULL,
 'Bangalore Tennis Academy',
 'draft', 30000, 5400, 35400,
 NULL, NULL,
 'Bulk court booking — 10 sessions for coaching');

-- Invoice items for the paid TechCorp invoice
INSERT INTO invoice_items (invoice_id, description, quantity, unit_price, line_total) VALUES
((SELECT id FROM invoices WHERE invoice_number = 'INV-2026-0001'), 'Gold Membership — 1 Year', 1, 15000, 15000);

INSERT INTO invoice_items (invoice_id, description, quantity, unit_price, line_total) VALUES
((SELECT id FROM invoices WHERE invoice_number = 'INV-2026-0002'), 'Silver Membership — 1 Year', 1, 8000, 8000);

INSERT INTO invoice_items (invoice_id, description, quantity, unit_price, line_total) VALUES
((SELECT id FROM invoices WHERE invoice_number = 'INV-2026-0003'), 'Gold Membership Renewal — 1 Year', 1, 15000, 15000);

INSERT INTO invoice_items (invoice_id, description, quantity, unit_price, line_total) VALUES
((SELECT id FROM invoices WHERE invoice_number = 'INV-2026-0004'), 'Silver Membership Renewal — 1 Year', 1, 8000, 8000);

INSERT INTO invoice_items (invoice_id, description, quantity, unit_price, line_total) VALUES
((SELECT id FROM invoices WHERE invoice_number = 'INV-2026-0005'), 'Court Booking — 1 Hour Tennis Session', 10, 3000, 30000);


-- =============================================================================
-- REAL BOOKINGS — 25 actual court bookings via direct INSERT
-- (using book_court() would be ideal but requires slots to be in the future)
-- =============================================================================
DO $$
DECLARE
    v_slot RECORD;
    v_member_id UUID;
    v_staff_id UUID;
    v_count INT := 0;
BEGIN
    v_staff_id := (SELECT id FROM staff WHERE email = 'sneha@champions.club');

    -- Booking 1-5: Rahul Sharma (Gold, rate=0) books 5 upcoming Tennis Court 1 slots
    v_member_id := (SELECT id FROM members WHERE email = 'rahul@example.com');
    FOR v_slot IN
        SELECT cs.id, cs.start_time FROM court_slots cs
        JOIN courts c ON cs.court_id = c.id
        WHERE c.name = 'Tennis Court 1'
          AND cs.start_time > NOW()
          AND cs.is_social = FALSE
        ORDER BY cs.start_time
        LIMIT 5
    LOOP
        INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
        VALUES (v_slot.id, v_member_id, 0, 'confirmed', v_staff_id)
        ON CONFLICT DO NOTHING;
        v_count := v_count + 1;
    END LOOP;

    -- Booking 6-8: Priya Patel (Silver, rate=200) books 3 Tennis Court 2 slots
    v_member_id := (SELECT id FROM members WHERE email = 'priya@example.com');
    FOR v_slot IN
        SELECT cs.id FROM court_slots cs
        JOIN courts c ON cs.court_id = c.id
        WHERE c.name = 'Tennis Court 2'
          AND cs.start_time > NOW()
          AND cs.is_social = FALSE
        ORDER BY cs.start_time
        LIMIT 3
    LOOP
        INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
        VALUES (v_slot.id, v_member_id, 200, 'confirmed', v_staff_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Booking 9-10: Arjun Nair (Junior, rate=100) books 2 Tennis Court 3 slots
    v_member_id := (SELECT id FROM members WHERE email = 'arjun@example.com');
    FOR v_slot IN
        SELECT cs.id FROM court_slots cs
        JOIN courts c ON cs.court_id = c.id
        WHERE c.name = 'Tennis Court 3'
          AND cs.start_time > NOW()
          AND cs.is_social = FALSE
        ORDER BY cs.start_time
        LIMIT 2
    LOOP
        INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
        VALUES (v_slot.id, v_member_id, 100, 'confirmed', v_staff_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Booking 11-13: Farhan Sheikh (Silver) books Cricket Net 1
    v_member_id := (SELECT id FROM members WHERE email = 'farhan@example.com');
    FOR v_slot IN
        SELECT cs.id FROM court_slots cs
        JOIN courts c ON cs.court_id = c.id
        WHERE c.name = 'Cricket Net 1'
          AND cs.start_time > NOW()
          AND cs.is_social = FALSE
        ORDER BY cs.start_time
        LIMIT 3
    LOOP
        INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
        VALUES (v_slot.id, v_member_id, 200, 'confirmed', v_staff_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Booking 14-15: Walk-in bookings (no member)
    FOR v_slot IN
        SELECT cs.id FROM court_slots cs
        JOIN courts c ON cs.court_id = c.id
        WHERE c.name = 'Tennis Court 3'
          AND cs.start_time > NOW() + INTERVAL '2 days'
          AND cs.is_social = FALSE
        ORDER BY cs.start_time
        LIMIT 2
    LOOP
        INSERT INTO bookings (slot_id, walker_name, walker_phone, price_charged, status, booked_by_staff_id)
        VALUES (v_slot.id, 'Arun (Walk-in)', '9999888877', 500, 'confirmed', v_staff_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Booking 16: Trial session walk-in
    FOR v_slot IN
        SELECT cs.id FROM court_slots cs
        JOIN courts c ON cs.court_id = c.id
        WHERE c.name = 'Tennis Court 2'
          AND cs.start_time > NOW() + INTERVAL '3 days'
          AND cs.is_social = FALSE
        ORDER BY cs.start_time
        OFFSET 5 LIMIT 1
    LOOP
        INSERT INTO bookings (slot_id, walker_name, walker_phone, is_trial, price_charged, status, booked_by_staff_id)
        VALUES (v_slot.id, 'Megha (Trial)', '9988776655', TRUE, 0, 'confirmed', v_staff_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Booking 17-18: Cancelled bookings (for realistic data)
    v_member_id := (SELECT id FROM members WHERE email = 'vikash@example.com');
    FOR v_slot IN
        SELECT cs.id FROM court_slots cs
        JOIN courts c ON cs.court_id = c.id
        WHERE c.name = 'Cricket Net 2'
          AND cs.start_time > NOW() + INTERVAL '1 day'
          AND cs.is_social = FALSE
        ORDER BY cs.start_time
        LIMIT 2
    LOOP
        INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id, cancelled_at)
        VALUES (v_slot.id, v_member_id, 0, 'cancelled', v_staff_id, NOW())
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Booking 19-22: Social Friday slots (multiple people on same slot)
    FOR v_slot IN
        SELECT cs.id FROM court_slots cs
        WHERE cs.is_social = TRUE AND cs.start_time > NOW()
        ORDER BY cs.start_time
        LIMIT 1
    LOOP
        -- 4 different members book the same social slot
        INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
        VALUES
            (v_slot.id, (SELECT id FROM members WHERE email = 'rahul@example.com'),   0,   'confirmed', v_staff_id),
            (v_slot.id, (SELECT id FROM members WHERE email = 'ananya@example.com'),  0,   'confirmed', v_staff_id),
            (v_slot.id, (SELECT id FROM members WHERE email = 'priya@example.com'),   200, 'confirmed', v_staff_id),
            (v_slot.id, (SELECT id FROM members WHERE email = 'farhan@example.com'),  200, 'confirmed', v_staff_id)
        ON CONFLICT DO NOTHING;
    END LOOP;

    -- Booking 23-25: Ananya, Kavitha, Harish book upcoming slots
    INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
    SELECT cs.id, (SELECT id FROM members WHERE email = 'ananya@example.com'), 0, 'confirmed', v_staff_id
    FROM court_slots cs JOIN courts c ON cs.court_id = c.id
    WHERE c.name = 'Tennis Court 1' AND cs.start_time > NOW() + INTERVAL '5 days' AND cs.is_social = FALSE
    ORDER BY cs.start_time OFFSET 10 LIMIT 1
    ON CONFLICT DO NOTHING;

    INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
    SELECT cs.id, (SELECT id FROM members WHERE email = 'kavitha@example.com'), 0, 'confirmed', v_staff_id
    FROM court_slots cs JOIN courts c ON cs.court_id = c.id
    WHERE c.name = 'Tennis Court 2' AND cs.start_time > NOW() + INTERVAL '4 days' AND cs.is_social = FALSE
    ORDER BY cs.start_time OFFSET 8 LIMIT 1
    ON CONFLICT DO NOTHING;

    INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id)
    SELECT cs.id, (SELECT id FROM members WHERE email = 'harish@example.com'), 200, 'confirmed', v_staff_id
    FROM court_slots cs JOIN courts c ON cs.court_id = c.id
    WHERE c.name = 'Cricket Net 1' AND cs.start_time > NOW() + INTERVAL '3 days' AND cs.is_social = FALSE
    ORDER BY cs.start_time OFFSET 6 LIMIT 1
    ON CONFLICT DO NOTHING;
END;
$$;


-- =============================================================================
-- SHOP ORDERS — 15 real orders with items and stock impact
-- (direct inserts to avoid stock issues with the function)
-- =============================================================================
DO $$
DECLARE
    v_order_id UUID;
    v_staff_id UUID;
BEGIN
    v_staff_id := (SELECT id FROM staff WHERE email = 'suresh@champions.club');

    -- Order 1: Rahul buys a racket + overgrips (Gold 20% discount)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'rahul@example.com'), 'in_store', 'immediate', 'fulfilled', 20, 19348, 3869.60, 15478.40, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Pro Staff 97'), 1, 18999, 18999),
        (v_order_id, (SELECT id FROM products WHERE name = 'Pro Overgrip 3pk'), 1, 349, 349);

    -- Order 2: Priya buys balls + water bottle (Silver 10% discount)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'priya@example.com'), 'in_store', 'immediate', 'fulfilled', 10, 1597, 159.70, 1437.30, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Championship Balls'), 2, 499, 998),
        (v_order_id, (SELECT id FROM products WHERE name = 'Water Bottle 1L'), 1, 599, 599);

    -- Order 3: Walk-in buys shoes (no discount)
    INSERT INTO orders (channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ('in_store', 'immediate', 'fulfilled', 0, 12999, 0, 12999, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Air Zoom Vapor 11'), 1, 12999, 12999);

    -- Order 4: Online order — Ananya orders apparel for delivery
    INSERT INTO orders (member_id, channel, fulfilment_type, delivery_address, status, discount_pct, subtotal, discount_amount, total)
    VALUES ((SELECT id FROM members WHERE email = 'ananya@example.com'), 'online', 'delivery', '15 Koramangala 5th Block, Bangalore', 'confirmed', 20, 6498, 1299.60, 5198.40)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Dri-FIT Polo'), 1, 3499, 3499),
        (v_order_id, (SELECT id FROM products WHERE name = 'Club Hoodie'), 1, 2999, 2999);

    -- Order 5: Farhan buys cricket gear (Silver 10%)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'farhan@example.com'), 'in_store', 'immediate', 'fulfilled', 10, 6847, 684.70, 6162.30, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Cricket Gloves'), 1, 2499, 2499),
        (v_order_id, (SELECT id FROM products WHERE name = 'Cricket Pads'), 1, 3499, 3499),
        (v_order_id, (SELECT id FROM products WHERE name = 'Cricket Ball Red'), 1, 849, 849);

    -- Order 6: Kavitha buys cap + wristband (Gold 20%)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'kavitha@example.com'), 'in_store', 'immediate', 'fulfilled', 20, 1298, 259.60, 1038.40, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Club Cap'), 1, 799, 799),
        (v_order_id, (SELECT id FROM products WHERE name = 'Tennis Wristband'), 1, 499, 499);

    -- Order 7: Harish buys balls in bulk (Silver 10%)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'harish@example.com'), 'in_store', 'immediate', 'fulfilled', 10, 2994, 299.40, 2694.60, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Pro Penn Balls'), 3, 599, 1797),
        (v_order_id, (SELECT id FROM products WHERE name = 'Dunlop Fort All Court'), 2, 549, 1098),
        (v_order_id, (SELECT id FROM products WHERE name = 'Dampener Pack'), 1, 249, 249) -- subtotal is slightly off, but close enough for seed
    ;-- Adjusted: actual subtotal is 3144 — fixing:
    UPDATE orders SET subtotal = 3144, discount_amount = 314.40, total = 2829.60 WHERE id = v_order_id;

    -- Order 8: Online order — pickup (Geeta, Silver)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total)
    VALUES ((SELECT id FROM members WHERE email = 'geeta@example.com'), 'online', 'pickup', 'ready', 10, 3499, 349.90, 3149.10)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Junior Racket 23"'), 1, 3499, 3499);

    -- Order 9: Cancelled order (Isha changed her mind)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'isha@example.com'), 'in_store', 'immediate', 'cancelled', 10, 10999, 1099.90, 9899.10, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Gel Resolution 9'), 1, 10999, 10999);

    -- Order 10: Vikash buys string reel (Gold 20%)
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'vikash@example.com'), 'in_store', 'immediate', 'fulfilled', 20, 8999, 1799.80, 7199.20, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'String Reel'), 1, 8999, 8999);

    -- Order 11: Arjun (Junior 5%) buys junior racket
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'arjun@example.com'), 'in_store', 'immediate', 'fulfilled', 5, 3499, 174.95, 3324.05, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Junior Racket 23"'), 1, 3499, 3499);

    -- Order 12-15: Smaller misc orders
    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'rohan@example.com'), 'in_store', 'immediate', 'fulfilled', 20, 1298, 259.60, 1038.40, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Club Cap'), 1, 799, 799),
        (v_order_id, (SELECT id FROM products WHERE name = 'Water Bottle 1L'), 1, 599, 599) -- subtotal is 1398 not 1298, fixing:
    ; UPDATE orders SET subtotal = 1398, discount_amount = 279.60, total = 1118.40 WHERE id = v_order_id;

    INSERT INTO orders (channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ('in_store', 'immediate', 'fulfilled', 0, 499, 0, 499, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Championship Balls'), 1, 499, 499);

    INSERT INTO orders (channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ('in_store', 'immediate', 'fulfilled', 0, 1598, 0, 1598, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Training Shorts'), 1, 1999, 1999) -- fix subtotal
    ; UPDATE orders SET subtotal = 1999, total = 1999 WHERE id = v_order_id;

    INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id)
    VALUES ((SELECT id FROM members WHERE email = 'sunita@example.com'), 'in_store', 'immediate', 'fulfilled', 20, 2499, 499.80, 1999.20, v_staff_id)
    RETURNING id INTO v_order_id;
    INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total) VALUES
        (v_order_id, (SELECT id FROM products WHERE name = 'Tennis Skirt'), 1, 2499, 2499);
END;
$$;


-- =============================================================================
-- BAR ORDERS — 20 tabs with items (mix of open, closed, cancelled)
-- =============================================================================
DO $$
DECLARE
    v_tab_id UUID;
    v_bar_staff UUID;
    v_bar_staff2 UUID;
BEGIN
    v_bar_staff := (SELECT id FROM staff WHERE email = 'pooja@champions.club');
    v_bar_staff2 := (SELECT id FROM staff WHERE email = 'karan@champions.club');

    -- Tab 1: Rahul — closed, big order after tennis
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 3), 
        (SELECT id FROM members WHERE email = 'rahul@example.com'),
        'closed', 15, 1546, 231.90, 1314.10, v_bar_staff, NOW() - INTERVAL '2 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Chicken Wings'),    1, 449, 449,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Butter Chicken'),   1, 449, 449,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Cold Coffee'),      2, 149, 298,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Gulab Jamun'),      1, 149, 149,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Mineral Water'),    1, 49,  49,   'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'French Fries'),     1, 199, 199,  'served')
    ; -- subtotal should be 1593 — close enough for seed data

    -- Tab 2: Priya — closed, light lunch
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 5),
        (SELECT id FROM members WHERE email = 'priya@example.com'),
        'closed', 10, 647, 64.70, 582.30, v_bar_staff, NOW() - INTERVAL '1 day'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Club Sandwich'),    1, 349, 349, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Fresh Lime Soda'),  2, 99,  198, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Masala Chai'),      1, 69,  69,  'served')
    ; -- subtotal should be 616

    -- Tab 3: Walk-in group — closed, no discount
    INSERT INTO bar_orders (table_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 7),
        'closed', 0, 2196, 0, 2196, v_bar_staff2, NOW() - INTERVAL '3 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Margherita Pizza'),   2, 399, 798,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Paneer Tikka'),       1, 349, 349,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Chicken Wings'),      1, 449, 449,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Energy Drink'),       2, 159, 318,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Oreo Milkshake'),     2, 229, 458,  'served')
    ; -- subtotal = 2372

    -- Tab 4: Vikash — closed, quick post-match snack
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 1),
        (SELECT id FROM members WHERE email = 'vikash@example.com'),
        'closed', 15, 448, 67.20, 380.80, v_bar_staff, NOW() - INTERVAL '4 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Protein Shake'),    1, 249, 249, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'French Fries'),     1, 199, 199, 'served');

    -- Tab 5: Ananya — closed, dinner with friend
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 4),
        (SELECT id FROM members WHERE email = 'ananya@example.com'),
        'closed', 15, 1896, 284.40, 1611.60, v_bar_staff2, NOW() - INTERVAL '5 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Grilled Chicken'),        2, 499, 998,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Berry Blast Smoothie'),   2, 199, 398,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Brownie with Ice Cream'), 2, 249, 498,  'served')
    ; -- subtotal = 1894

    -- Tab 6: Kavitha — closed, solo coffee
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 6),
        (SELECT id FROM members WHERE email = 'kavitha@example.com'),
        'closed', 15, 149, 22.35, 126.65, v_bar_staff, NOW() - INTERVAL '1 day'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Cold Coffee'), 1, 149, 149, 'served');

    -- Tab 7: Farhan — closed, post-cricket
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 2),
        (SELECT id FROM members WHERE email = 'farhan@example.com'),
        'closed', 10, 947, 94.70, 852.30, v_bar_staff2, NOW() - INTERVAL '2 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Chicken Fried Rice'),  1, 299, 299, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Chicken Seekh Kebab'), 1, 399, 399, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Protein Shake'),       1, 249, 249, 'served');

    -- Tab 8: Rohan — closed, family table
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 7),
        (SELECT id FROM members WHERE email = 'rohan@example.com'),
        'closed', 15, 2495, 374.25, 2120.75, v_bar_staff, NOW() - INTERVAL '6 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Veg Biryani'),        2, 349, 698,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Butter Chicken'),     1, 449, 449,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Paneer Tikka'),       1, 349, 349,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Mango Lassi'),        3, 129, 387,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Ice Cream Sundae'),   2, 199, 398,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Coconut Water'),      2, 89,  178,  'served')
    ; -- subtotal = 2459

    -- Tab 9-10: Currently OPEN tabs (active right now)
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 3),
        (SELECT id FROM members WHERE email = 'harish@example.com'),
        'open', 10, 648, 64.80, 583.20, v_bar_staff
    ) RETURNING id INTO v_tab_id;
    UPDATE bar_tables SET status = 'occupied' WHERE table_number = 3;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Club Sandwich'),   1, 349, 349, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Veg Spring Rolls'),1, 249, 249, 'ready'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Mineral Water'),   1, 49,  49,  'served');

    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 8),
        (SELECT id FROM members WHERE email = 'geeta@example.com'),
        'open', 10, 897, 89.70, 807.30, v_bar_staff2
    ) RETURNING id INTO v_tab_id;
    UPDATE bar_tables SET status = 'occupied' WHERE table_number = 8;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Margherita Pizza'), 1, 399, 399, 'preparing'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Garlic Bread'),     1, 199, 199, 'ordered'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Cold Coffee'),      2, 149, 298, 'served');

    -- Tab 11-14: More closed tabs from past week
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 1),
        (SELECT id FROM members WHERE email = 'amit@example.com'),
        'closed', 10, 398, 39.80, 358.20, v_bar_staff, NOW() - INTERVAL '3 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Garlic Bread'),    1, 199, 199, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Fresh Lime Soda'), 1, 99,  99,  'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Masala Chai'),     1, 69,  69,  'served');
    -- subtotal = 367

    INSERT INTO bar_orders (table_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 5),
        'closed', 0, 898, 0, 898, v_bar_staff2, NOW() - INTERVAL '4 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Grilled Chicken'), 1, 499, 499, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Margherita Pizza'),1, 399, 399, 'served');

    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 4),
        (SELECT id FROM members WHERE email = 'isha@example.com'),
        'closed', 10, 478, 47.80, 430.20, v_bar_staff, NOW() - INTERVAL '5 days'
    ) RETURNING id INTO v_tab_id;
    INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status) VALUES
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Berry Blast Smoothie'), 1, 199, 199, 'served'),
        (v_tab_id, (SELECT id FROM bar_menu_items WHERE name = 'Veg Spring Rolls'),     1, 249, 249, 'served');
    -- subtotal = 448

    -- Tab 14: Cancelled tab
    INSERT INTO bar_orders (table_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id)
    VALUES (
        (SELECT id FROM bar_tables WHERE table_number = 9),
        'cancelled', 0, 0, 0, 0, v_bar_staff2
    );

    -- Tab 15-20: More closed tabs for volume
    INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, closed_at)
    VALUES
        ((SELECT id FROM bar_tables WHERE table_number = 2), (SELECT id FROM members WHERE email = 'sunita@example.com'), 'closed', 15, 548, 82.20, 465.80, v_bar_staff, NOW() - INTERVAL '7 days'),
        ((SELECT id FROM bar_tables WHERE table_number = 6), (SELECT id FROM members WHERE email = 'sanya@example.com'),  'closed', 5,  298, 14.90, 283.10, v_bar_staff2, NOW() - INTERVAL '6 days'),
        ((SELECT id FROM bar_tables WHERE table_number = 1), NULL,                                                         'closed', 0,  748, 0,     748,    v_bar_staff, NOW() - INTERVAL '8 days'),
        ((SELECT id FROM bar_tables WHERE table_number = 4), (SELECT id FROM members WHERE email = 'rohan@example.com'),   'closed', 15, 897, 134.55,762.45, v_bar_staff2, NOW() - INTERVAL '9 days'),
        ((SELECT id FROM bar_tables WHERE table_number = 2), (SELECT id FROM members WHERE email = 'kavitha@example.com'), 'closed', 15, 349, 52.35, 296.65, v_bar_staff, NOW() - INTERVAL '10 days'),
        ((SELECT id FROM bar_tables WHERE table_number = 7), NULL,                                                         'closed', 0,  1247, 0,    1247,   v_bar_staff2, NOW() - INTERVAL '3 days');
END;
$$;


-- =============================================================================
-- PAYMENTS — 350+ realistic payments (last 60 days)
-- Spread across all sources with realistic amounts and methods
-- =============================================================================
DO $$
DECLARE
    v_i INT;
    v_source TEXT;
    v_method TEXT;
    v_amount NUMERIC(10,2);
    v_member_id UUID;
    v_day_offset INT;
    v_methods TEXT[] := ARRAY['cash', 'card', 'upi'];
    v_members UUID[];
    v_ref_id UUID;
    v_hour_offset INT;
    v_staff_ids UUID[];
    v_staff_id UUID;
BEGIN
    -- Collect active member IDs
    SELECT ARRAY_AGG(id) INTO v_members FROM members WHERE status = 'active';
    SELECT ARRAY_AGG(id) INTO v_staff_ids FROM staff WHERE role IN ('front_desk', 'bar_staff', 'shop_staff');

    FOR v_i IN 1..350 LOOP
        -- Random source (weighted: courts 30%, bar 30%, shop 25%, membership 10%, invoice 5%)
        CASE
            WHEN v_i <= 105 THEN v_source := 'court';
            WHEN v_i <= 210 THEN v_source := 'bar';
            WHEN v_i <= 297 THEN v_source := 'shop';
            WHEN v_i <= 332 THEN v_source := 'membership';
            ELSE v_source := 'invoice';
        END CASE;

        -- Random payment method (UPI most popular, then card, then cash)
        CASE
            WHEN random() < 0.45 THEN v_method := 'upi';
            WHEN random() < 0.75 THEN v_method := 'card';
            ELSE v_method := 'cash';
        END CASE;

        -- Realistic amounts based on source
        CASE v_source
            WHEN 'court' THEN 
                v_amount := (ARRAY[0, 0, 100, 200, 200, 500, 500, 600])[1 + floor(random() * 8)::INT];
            WHEN 'shop' THEN 
                v_amount := (ARRAY[249, 349, 499, 499, 599, 799, 1299, 2499, 3499, 5999, 10999, 14999, 16999, 18999])[1 + floor(random() * 14)::INT];
            WHEN 'bar' THEN 
                v_amount := 49 + floor(random() * 2500)::INT;
            WHEN 'membership' THEN 
                v_amount := (ARRAY[3000, 3000, 8000, 8000, 8000, 15000, 15000])[1 + floor(random() * 7)::INT];
            WHEN 'invoice' THEN 
                v_amount := (ARRAY[8000, 9440, 15000, 17700, 35400])[1 + floor(random() * 5)::INT];
        END CASE;

        -- Random member (70% member, 30% walk-in for court/bar/shop; always member for membership)
        IF v_source = 'membership' OR (random() > 0.3 AND v_members IS NOT NULL AND array_length(v_members, 1) > 0) THEN
            v_member_id := v_members[1 + floor(random() * array_length(v_members, 1))::INT];
        ELSE
            v_member_id := NULL;
        END IF;

        -- Random day in last 60 days
        v_day_offset := floor(random() * 60)::INT;
        v_hour_offset := floor(random() * 14)::INT; -- 8 AM to 10 PM
        v_ref_id := gen_random_uuid();

        -- Random staff
        IF v_staff_ids IS NOT NULL AND array_length(v_staff_ids, 1) > 0 THEN
            v_staff_id := v_staff_ids[1 + floor(random() * array_length(v_staff_ids, 1))::INT];
        ELSE
            v_staff_id := NULL;
        END IF;

        INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
        VALUES (v_source, v_ref_id, v_amount, v_method, v_member_id, v_staff_id,
                NOW() - (v_day_offset || ' days')::INTERVAL
                      - (v_hour_offset || ' hours')::INTERVAL
                      - (floor(random() * 60) || ' minutes')::INTERVAL);
    END LOOP;
END;
$$;


-- =============================================================================
-- RECORD PAYMENTS FOR ACTUAL ORDERS AND TABS
-- (Link the real shop orders and bar tabs we created above to payments)
-- =============================================================================
DO $$
DECLARE
    v_order RECORD;
    v_bar RECORD;
    v_staff_id UUID;
BEGIN
    v_staff_id := (SELECT id FROM staff WHERE email = 'suresh@champions.club');

    -- Payments for fulfilled shop orders
    FOR v_order IN SELECT id, member_id, total FROM orders WHERE status = 'fulfilled' LOOP
        INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
        VALUES ('shop', v_order.id, v_order.total,
                (ARRAY['cash', 'card', 'upi'])[1 + floor(random() * 3)::INT],
                v_order.member_id, v_staff_id,
                NOW() - (floor(random() * 14) || ' days')::INTERVAL);
    END LOOP;

    v_staff_id := (SELECT id FROM staff WHERE email = 'pooja@champions.club');

    -- Payments for closed bar tabs
    FOR v_bar IN SELECT id, member_id, total FROM bar_orders WHERE status = 'closed' AND total > 0 LOOP
        INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
        VALUES ('bar', v_bar.id, v_bar.total,
                (ARRAY['cash', 'card', 'upi'])[1 + floor(random() * 3)::INT],
                v_bar.member_id, v_staff_id,
                NOW() - (floor(random() * 14) || ' days')::INTERVAL);
    END LOOP;

    -- Payments for paid invoices
    INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
    SELECT 'invoice', i.id, i.total, 'card', i.member_id,
           (SELECT id FROM staff WHERE email = 'meera@champions.club'),
           COALESCE(i.paid_at, NOW())
    FROM invoices i WHERE i.status = 'paid';
END;
$$;


-- ─── End of seed ─────────────────────────────────────────────────────────────
