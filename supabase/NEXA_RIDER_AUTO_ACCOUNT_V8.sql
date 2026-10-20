-- NEXA Rider account auto-link guard (V8)
-- Safe to run after Rider GPS V7. Does not delete rider/order data.

-- One application login must never point to more than one rider.
CREATE UNIQUE INDEX IF NOT EXISTS pos_riders_profile_id_unique
ON public.pos_riders(profile_id)
WHERE profile_id IS NOT NULL;

-- Helpful lookup indexes for rider creation/linking and assigned orders.
CREATE INDEX IF NOT EXISTS pos_riders_branch_phone_idx
ON public.pos_riders(branch_id, phone);

CREATE INDEX IF NOT EXISTS pos_orders_rider_id_idx
ON public.pos_orders(rider_id);

COMMENT ON COLUMN public.pos_riders.profile_id IS
'Auth/pos_profiles login linked to this rider. New Delivery Boy accounts are linked automatically by the create-staff Edge Function.';
