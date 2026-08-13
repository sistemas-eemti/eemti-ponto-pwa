-- Consulta autenticada das proprias marcacoes para o Mobile pessoal.

create or replace function public.employee_punch_history(
  p_enrollment text,
  p_device_id text,
  p_pin text default null,
  p_token text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_employee public.employees%rowtype;
  v_device_id uuid;
  v_token text := '';
begin
  if trim(coalesce(p_enrollment, '')) = '' or trim(coalesce(p_device_id, '')) = '' then
    return jsonb_build_object('ok', false, 'message', 'Matrícula e dispositivo são obrigatórios.');
  end if;

  select * into v_employee
  from public.employees
  where enrollment = trim(p_enrollment) and active = true;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Funcionário não encontrado ou inativo.');
  end if;

  insert into public.devices (client_device_id, channel, last_seen_at)
  values (p_device_id, 'mobile', now())
  on conflict (client_device_id) do update set last_seen_at = now(), channel = excluded.channel
  returning id into v_device_id;

  if coalesce(p_pin, '') <> '' then
    if v_employee.pin_hash is null or v_employee.pin_hash <> extensions.crypt(p_pin, v_employee.pin_hash) then
      return jsonb_build_object('ok', false, 'message', 'PIN incorreto.');
    end if;
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.device_tokens (employee_id, device_id, token_hash, expires_at)
    values (v_employee.id, v_device_id, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '72 hours');
  elsif exists (
    select 1 from public.device_tokens
    where employee_id = v_employee.id and device_id = v_device_id
      and token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
      and expires_at > now()
  ) then
    update public.device_tokens set last_used_at = now()
    where employee_id = v_employee.id and device_id = v_device_id
      and token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
    v_token := p_token;
  else
    return jsonb_build_object('ok', false, 'message', 'Informe o PIN para consultar suas marcações.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'token', v_token,
    'name', v_employee.name,
    'rows', coalesce((
      select jsonb_agg(row_to_json(x)) from (
        select to_char(p.captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') as captured_at,
               p.origin, p.captured_offline, p.inside_geofence, p.distance_meters
        from public.punches p
        where p.employee_id = v_employee.id and p.excluded_at is null
        order by p.captured_at desc
        limit 100
      ) x
    ), '[]'::jsonb)
  );
end;
$$;

revoke all on function public.employee_punch_history(text, text, text, text) from public, anon, authenticated;
grant execute on function public.employee_punch_history(text, text, text, text) to service_role;

select pg_notify('pgrst', 'reload schema');
