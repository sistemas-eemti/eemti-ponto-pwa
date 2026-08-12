-- Ponte JSON para a Data API. Evita ambiguidade de tipos do PostgREST ao
-- chamar sync_punch com parâmetros opcionais numéricos e timestamps.

create or replace function public.sync_punch_api(p_payload jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.sync_punch(
    p_client_record_id := p_payload->>'client_record_id',
    p_channel := p_payload->>'channel',
    p_device_id := p_payload->>'device_id',
    p_enrollment := p_payload->>'enrollment',
    p_captured_at := (p_payload->>'captured_at')::timestamptz,
    p_offline := coalesce((p_payload->>'offline')::boolean, false),
    p_latitude := nullif(p_payload->>'latitude', '')::numeric,
    p_longitude := nullif(p_payload->>'longitude', '')::numeric,
    p_accuracy_meters := nullif(p_payload->>'accuracy_meters', '')::numeric,
    p_pin := nullif(p_payload->>'pin', ''),
    p_token := nullif(p_payload->>'token', '')
  );
end;
$$;

revoke all on function public.sync_punch_api(jsonb) from public, anon, authenticated;
grant execute on function public.sync_punch_api(jsonb) to service_role;
