# Assumptions & Open Questions

## Assumptions Made

1. **Sports**: Seeded with Tennis and Cricket (per "Meet the Club" scene). The `sports` table is configurable — adding padel/badminton is just an INSERT.

2. **Social Play**: Modeled as `is_social` flag on individual court slots, not restricted to Fridays at the DB level. Seeded with Friday 7 PM–10 PM as social. UI can offer a "Mark as Social" toggle for admin.

3. **Session Overlap**: Slots are 1-hour blocks starting every 30 minutes (e.g., 6:00–7:00, 6:30–7:30). Each slot is an independent row. The booking constraint is per-slot, not across overlapping slots. Two people can book adjacent overlapping slots on the same court (6:00 and 6:30) — they just can't book the **same** slot.

4. **Bar Tab Scope**: One open tab per table at a time. A member can be linked for discount. If a table has multiple groups, staff creates separate tabs (close one, open another).

5. **Trial Sessions**: Priced at ₹0 for all plans and walk-ins (configurable via `plans.trial_rate` and `book_court(is_trial=TRUE)`).

6. **Junior Age Check**: Enforced only at registration via `register_member()`. A junior must have `date_of_birth` provided and be under 18.

7. **Walk-in Purchases**: Walk-ins (no member_id) can buy from the shop and bar at full price. No discount applied.

8. **Delivery Logistics**: The `delivery` fulfilment type stores a delivery address, but actual shipping/delivery tracking is out of scope.

9. **Payroll**: Simplified to monthly salary from `staff.monthly_salary`. One payroll record per staff per month. Deductions are a single field (no PF/ESI breakdown).

10. **Tax**: Revenue views provide totals by source and month. Specific GST/tax rates and filing are out of scope for the 24-hour build.

11. **Invoicing**: Invoices are created manually by admin/owner. Auto-generation of membership renewal invoices is a future enhancement.

12. **Auth**: Using simple JWT + bcrypt for the hackathon. Staff roles are stored in the `staff` table. No member-facing login (members don't log into the system; staff operates on their behalf). The `X-Dev-Role` header bypasses auth during development.

13. **Slot Generation**: Seed script pre-generates slots for 7 days. In production, a cron job or on-demand generation would extend the calendar further.

14. **Double-Booking Enforcement**: Handled via `SELECT ... FOR UPDATE` row lock in `book_court()`, not via exclusion constraints on overlapping time ranges. This is simpler and sufficient since slots are discrete rows.

15. **Overlapping 30-min Slot Semantics**: The PDF says "a new slot opens every half hour" and "sessions last an hour." We model this as discrete slot rows. A court with slots at 6:00–7:00 and 6:30–7:30 can have *different* bookings — they are separate sessions that happen to overlap in physical time. The club presumably manages this operationally (e.g., the 6:00 player wraps up by 7:00, the 6:30 player starts by 6:30). If the club wants to prevent overlapping sessions, they can simply not generate 30-min-offset slots.

---

## Open Questions (for the team to resolve)

1. **Should members have their own login?** Current design: no. Members are managed by staff. Adding member self-service (booking from phone, viewing history) would require a member auth flow and potentially Supabase Auth with RLS.

2. **Multiple bookings on the same court at overlapping times**: See Assumption #15 above. Does the club actually let two people play on the same court at overlapping times via the 30-min offset? If not, we need an exclusion constraint on `(court_id, tstzrange(start_time, end_time))` to prevent it.

3. **Cancellation refund**: Currently `cancel_booking()` just marks the booking as cancelled. Should it also create a negative payment (refund) in the payments table? For the hackathon, we skip refunds.

4. **Walk-in daily limit**: Walk-ins don't have a member_id, so the daily limit doesn't apply to them. Is that intentional? (Assumed yes — they're one-off visitors.)

5. **Bar item availability**: `bar_menu_items.is_available` is a manual toggle. There's no stock tracking for bar/kitchen items (unlike the shop). Is that acceptable? (Assumed yes for MVP.)
