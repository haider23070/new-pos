NEXA Rider v7 repair

1. Open Supabase > SQL Editor.
2. Run ONLY: supabase/NEXA_POS_RIDER_GPS_V7.sql
   You do not need to rerun V5 or V6.
3. Restart the app and log in as Rider.
4. Tap Check In and allow Location permission.

V7 removes the invalid min(uuid) code and replaces the V6 rider RPC functions cleanly.
It does not delete riders, orders, attendance, or GPS history.
