-- NEXA profile/layout/expense features.
-- The existing pos_expenses table already supports the implemented expense workflow.
-- This script only ensures API grants and reloads the schema cache.
grant usage on schema public to authenticated;
grant select,insert,update,delete on public.pos_expenses to authenticated;
grant select,update on public.pos_profiles to authenticated;
notify pgrst, 'reload schema';
