-- Persist restaurant GPS safely. Developer may configure any branch; Admin only their own.
DROP FUNCTION IF EXISTS public.nexa_save_branch_location(uuid,numeric,numeric,integer,numeric);
CREATE FUNCTION public.nexa_save_branch_location(
  p_branch_id uuid,
  p_latitude numeric,
  p_longitude numeric,
  p_attendance_radius_m integer DEFAULT 500,
  p_delivery_radius_km numeric DEFAULT 8
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_uid uuid:=auth.uid(); v_role text; v_home uuid; v_saved public.branches%ROWTYPE;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  SELECT p.role,p.branch_id INTO v_role,v_home FROM public.profiles p WHERE p.id=v_uid AND coalesce(p.active,true)=true LIMIT 1;
  IF v_role IS NULL THEN RAISE EXCEPTION 'Active staff profile not found'; END IF;
  IF v_role='Developer' THEN NULL;
  ELSIF v_role='Admin' THEN IF v_home IS NULL OR v_home<>p_branch_id THEN RAISE EXCEPTION 'Admin can configure only their own branch'; END IF;
  ELSE RAISE EXCEPTION 'Only Developer or Admin can configure branch location'; END IF;
  IF p_latitude IS NULL OR p_latitude < -90 OR p_latitude > 90 THEN RAISE EXCEPTION 'Invalid latitude'; END IF;
  IF p_longitude IS NULL OR p_longitude < -180 OR p_longitude > 180 THEN RAISE EXCEPTION 'Invalid longitude'; END IF;
  IF p_attendance_radius_m IS NULL OR p_attendance_radius_m < 50 OR p_attendance_radius_m > 10000 THEN RAISE EXCEPTION 'Attendance radius must be between 50 and 10000 metres'; END IF;
  IF p_delivery_radius_km IS NULL OR p_delivery_radius_km <= 0 OR p_delivery_radius_km > 500 THEN RAISE EXCEPTION 'Invalid delivery radius'; END IF;
  UPDATE public.branches SET latitude=p_latitude,longitude=p_longitude,attendance_radius_m=p_attendance_radius_m,delivery_radius_km=p_delivery_radius_km WHERE id=p_branch_id RETURNING * INTO v_saved;
  IF v_saved.id IS NULL THEN RAISE EXCEPTION 'Branch not found'; END IF;
  RETURN jsonb_build_object('success',true,'branch_id',v_saved.id,'branch_name',v_saved.name,'latitude',v_saved.latitude,'longitude',v_saved.longitude,'attendance_radius_m',v_saved.attendance_radius_m,'delivery_radius_km',v_saved.delivery_radius_km);
END $$;
REVOKE ALL ON FUNCTION public.nexa_save_branch_location(uuid,numeric,numeric,integer,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nexa_save_branch_location(uuid,numeric,numeric,integer,numeric) TO authenticated;
NOTIFY pgrst,'reload schema';
