-- =============================================================================
-- CHAMPIONS CLUB — SEED 2 (MASSIVE TRANSACTIONAL DATA)
-- This script generates hundreds of bookings, orders, and payments for the 
-- past 30 days to make the analytics and dashboard look incredibly realistic!
-- It safely references existing data from seed1.sql.
-- =============================================================================

DO $$
DECLARE
    v_staff_id UUID;
    v_member RECORD;
    v_product RECORD;
    v_menu_item RECORD;
    v_court RECORD;
    v_slot_id UUID;
    v_order_id UUID;
    v_bar_order_id UUID;
    v_invoice_id UUID;
    v_date DATE;
    v_timestamp TIMESTAMPTZ;
    v_random_qty INT;
    i INT;
    j INT;
BEGIN
    -- Get a default staff member to attribute actions to
    SELECT id INTO v_staff_id FROM staff WHERE role IN ('admin', 'owner', 'manager') LIMIT 1;

    -- =========================================================================
    -- 1. MASSIVE COURT BOOKINGS (Past 30 days + Today)
    -- =========================================================================
    FOR v_court IN SELECT id, walk_in_rate FROM courts LOOP
        FOR i IN 1..30 LOOP
            v_date := CURRENT_DATE - (i || ' days')::INTERVAL;
            
            -- Create 3 random slots per day in the past for each court
            FOR j IN 1..3 LOOP
                v_timestamp := (v_date + (8 + floor(random() * 12) || ' hours')::INTERVAL)::TIMESTAMPTZ;
                
                -- Insert slot safely
                INSERT INTO court_slots (court_id, start_time, end_time, is_social)
                VALUES (v_court.id, v_timestamp, v_timestamp + INTERVAL '1 hour', false)
                ON CONFLICT (court_id, start_time) DO NOTHING
                RETURNING id INTO v_slot_id;
                
                -- If slot was created or already existed, grab its ID
                IF v_slot_id IS NULL THEN
                    SELECT id INTO v_slot_id FROM court_slots WHERE court_id = v_court.id AND start_time = v_timestamp;
                END IF;

                -- Get a random member
                SELECT * INTO v_member FROM members ORDER BY random() LIMIT 1;

                -- Insert Booking
                INSERT INTO bookings (slot_id, member_id, price_charged, status, booked_by_staff_id, created_at)
                VALUES (v_slot_id, v_member.id, v_court.walk_in_rate * 0.5, 'completed', v_staff_id, v_timestamp - INTERVAL '2 days')
                ON CONFLICT DO NOTHING;

                -- Insert Payment for the booking
                INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
                VALUES ('court', v_slot_id, v_court.walk_in_rate * 0.5, 
                        CASE WHEN random() > 0.5 THEN 'card' ELSE 'upi' END, 
                        v_member.id, v_staff_id, v_timestamp);
            END LOOP;
        END LOOP;
    END LOOP;

    -- =========================================================================
    -- 2. MASSIVE SHOP ORDERS (100 random orders over 30 days)
    -- =========================================================================
    FOR i IN 1..100 LOOP
        v_timestamp := NOW() - (random() * 30 || ' days')::INTERVAL;
        SELECT * INTO v_member FROM members ORDER BY random() LIMIT 1;
        SELECT * INTO v_product FROM products WHERE is_active = TRUE ORDER BY random() LIMIT 1;
        v_random_qty := floor(random() * 3) + 1;

        -- Create Order
        INSERT INTO orders (member_id, channel, fulfilment_type, status, discount_pct, subtotal, discount_amount, total, placed_by_staff_id, created_at, updated_at)
        VALUES (v_member.id, 'in_store', 'immediate', 'fulfilled', 10, v_product.price * v_random_qty, (v_product.price * v_random_qty) * 0.1, (v_product.price * v_random_qty) * 0.9, v_staff_id, v_timestamp, v_timestamp)
        RETURNING id INTO v_order_id;

        -- Create Order Item
        INSERT INTO order_items (order_id, product_id, quantity, unit_price, line_total, created_at)
        VALUES (v_order_id, v_product.id, v_random_qty, v_product.price, v_product.price * v_random_qty, v_timestamp);

        -- Create Payment
        INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
        VALUES ('shop', v_order_id, (v_product.price * v_random_qty) * 0.9, 
                CASE WHEN random() > 0.3 THEN 'card' ELSE 'cash' END, 
                v_member.id, v_staff_id, v_timestamp);
    END LOOP;

    -- =========================================================================
    -- 3. MASSIVE BAR ORDERS (150 random tabs over 30 days)
    -- =========================================================================
    FOR i IN 1..150 LOOP
        v_timestamp := NOW() - (random() * 30 || ' days')::INTERVAL;
        SELECT * INTO v_member FROM members ORDER BY random() LIMIT 1;
        SELECT * INTO v_menu_item FROM bar_menu_items WHERE is_available = TRUE ORDER BY random() LIMIT 1;
        v_random_qty := floor(random() * 4) + 1;

        -- Create Bar Order
        INSERT INTO bar_orders (table_id, member_id, status, discount_pct, subtotal, discount_amount, total, served_by_staff_id, opened_at, closed_at, created_at)
        VALUES (
            (SELECT id FROM bar_tables ORDER BY random() LIMIT 1), 
            v_member.id, 'closed', 5, v_menu_item.price * v_random_qty, (v_menu_item.price * v_random_qty) * 0.05, (v_menu_item.price * v_random_qty) * 0.95, 
            v_staff_id, v_timestamp - INTERVAL '1 hour', v_timestamp, v_timestamp
        )
        RETURNING id INTO v_bar_order_id;

        -- Create Bar Order Item
        INSERT INTO bar_order_items (bar_order_id, menu_item_id, quantity, unit_price, line_total, kitchen_status, created_at)
        VALUES (v_bar_order_id, v_menu_item.id, v_random_qty, v_menu_item.price, v_menu_item.price * v_random_qty, 'served', v_timestamp);

        -- Create Payment
        INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
        VALUES ('bar', v_bar_order_id, (v_menu_item.price * v_random_qty) * 0.95, 
                CASE WHEN random() > 0.2 THEN 'upi' ELSE 'card' END, 
                v_member.id, v_staff_id, v_timestamp);
    END LOOP;

    -- =========================================================================
    -- 4. MASSIVE INVOICES (20 random invoices over 30 days)
    -- =========================================================================
    FOR i IN 1..20 LOOP
        v_timestamp := NOW() - (random() * 30 || ' days')::INTERVAL;
        SELECT * INTO v_member FROM members ORDER BY random() LIMIT 1;

        INSERT INTO invoices (invoice_number, member_id, status, subtotal, tax_amount, total, due_date, paid_at, created_at, updated_at)
        VALUES (
            'INV-2026-M' || LPAD(i::TEXT, 3, '0'), 
            v_member.id, 'paid', 5000, 900, 5900, v_timestamp::DATE, v_timestamp + INTERVAL '2 days', v_timestamp, v_timestamp + INTERVAL '2 days'
        )
        RETURNING id INTO v_invoice_id;

        INSERT INTO invoice_items (invoice_id, description, quantity, unit_price, line_total, created_at)
        VALUES (v_invoice_id, 'Monthly Coaching Fee', 1, 5000, 5000, v_timestamp);

        INSERT INTO payments (source, reference_id, amount, method, member_id, received_by_staff_id, created_at)
        VALUES ('invoice', v_invoice_id, 5900, 'card', v_member.id, v_staff_id, v_timestamp + INTERVAL '2 days');
    END LOOP;

END $$;
