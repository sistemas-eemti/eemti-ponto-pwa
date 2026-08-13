-- Mantem a resposta da batida como objeto mesmo sem mensagem ao funcionario.

create or replace function public.sync_punch_api(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_result jsonb;
  v_message text;
begin
  v_result := public.sync_punch(
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

  if (v_result->>'ok') = 'true' then
    select value #>> '{}' into v_message
    from public.settings
    where key = 'mensagem_funcionario';
    if nullif(trim(coalesce(v_message, '')), '') is not null then
      v_result := jsonb_set(v_result, '{aviso}', to_jsonb(v_message), true);
    end if;
  end if;

  return v_result;
end;
$$;

revoke all on function public.sync_punch_api(jsonb) from public, anon, authenticated;
grant execute on function public.sync_punch_api(jsonb) to service_role;

select pg_notify('pgrst', 'reload schema');
