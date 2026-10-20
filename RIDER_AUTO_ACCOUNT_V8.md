# Rider automatic account creation — V8

Future rider creation is automatic from Staff Management.

When Admin/Manager adds an employee with role **Delivery Boy**, the `create-staff` Edge Function now:
1. Creates the Supabase Auth login.
2. Creates `pos_profiles` using only the confirmed columns.
3. Finds an existing unlinked `pos_riders` record by branch + phone, then branch + exact name; otherwise creates a new rider.
4. Sets `pos_riders.profile_id` to the new login ID automatically.
5. Initializes the rider as Available / Off Duty.

No manual UUID linking is required for future riders.

## Required deployment
Run `supabase/NEXA_RIDER_AUTO_ACCOUNT_V8.sql` once in SQL Editor.
Then deploy the included Edge Function:

`supabase functions deploy create-staff`

The Supabase project must have the normal `SUPABASE_SERVICE_ROLE_KEY` secret available to Edge Functions.
