# Rider Tracking v10
- Admin/Manager Rider Location now includes date-based historical GPS review.
- Stops are detected when the rider remains within about 50 metres for at least 5 minutes.
- Each stop shows start/end time, duration and coordinates.
- Rider app stores a GPS heartbeat every 60 seconds while the web app is active and checked in, improving stationary-time evidence.
- Existing `pos_rider_locations` is the audit/history table; records remain available for later/night review.
- Run `supabase/NEXA_RIDER_HISTORY_V10.sql` once for history query indexes.

Important: normal mobile browsers can suspend JavaScript/GPS when the browser is closed, killed, or heavily backgrounded. Continuous locked-screen/background GPS requires a native/PWA background-location implementation supported by the target device.
