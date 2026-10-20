-- NEXA Rider History v10
-- Existing pos_rider_locations rows are the permanent GPS history.
-- This adds indexes for fast nightly/day history review. No history is deleted.
create index if not exists pos_rider_locations_branch_time_idx
  on public.pos_rider_locations(branch_id, recorded_at desc);
create index if not exists pos_rider_locations_rider_day_idx
  on public.pos_rider_locations(rider_id, recorded_at desc);
