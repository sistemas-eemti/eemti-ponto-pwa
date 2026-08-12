-- Registro transacional de batida para uso exclusivo do Cloudflare Worker.
-- PINs novos usam bcrypt (pgcrypto crypt); o navegador nunca recebe hashes.

create or replace function public.sync_punch(
  p_client_record_id text,
  p_channel text,
  p_device_id text,
  p_enrollment text,
  p_captured_at timestamptz,
  p_offline boolean default false,
  p_latitude numeric default null,
  p_longitude numeric default null,
  p_accuracy_meters numeric default null,
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
  v_previous_hash text := '';
  v_hash text;
  v_origin text;
  v_recorded_at timestamptz := now();
  v_effective_at timestamptz;
  v_geofence_id uuid;
  v_distance numeric;
  v_inside boolean;
  v_token text := '';
  v_latest_at timestamptz;
  v_latest_captured_at timestamptz;
  v_existing public.punches%rowtype;
begin
  if p_client_record_id !~ '^[A-Za-z0-9_-]{8,80}$' or p_device_id !~ '^[A-Za-z0-9_-]{8,160}$' then
    return jsonb_build_object('ok', false, 'message', 'Identificador do dispositivo inválido.');
  end if;
  if p_channel not in ('mobile', 'kiosk') then
    return jsonb_build_object('ok', false, 'message', 'Canal inválido.');
  end if;
  if p_captured_at is null or p_captured_at > now() + interval '5 minutes' then
    return jsonb_build_object('ok', false, 'message', 'Data da batida inválida.');
  end if;
  if p_channel = 'mobile' and (p_latitude is null or p_longitude is null) then
    return jsonb_build_object('ok', false, 'message', 'Localização da batida inválida.');
  end if;

  -- Serializa as gravações para preservar cadeia de hash e anti-duplicidade.
  perform pg_advisory_xact_lock(186792024);

  select * into v_existing from public.punches where client_record_id = p_client_record_id;
  if found then
    return jsonb_build_object('ok', true, 'already_synced', true, 'message', 'Batida já sincronizada.');
  end if;

  select * into v_employee from public.employees where enrollment = trim(p_enrollment) and active = true;
  if not found then
    return jsonb_build_object('ok', false, 'message', 'Funcionário não encontrado ou inativo.');
  end if;

  insert into public.devices (client_device_id, channel, last_seen_at)
  values (p_device_id, p_channel, now())
  on conflict (client_device_id) do update set last_seen_at = now(), channel = excluded.channel
  returning id into v_device_id;

  if coalesce(p_pin, '') <> '' then
    if v_employee.pin_hash is null or v_employee.pin_hash <> extensions.crypt(p_pin, v_employee.pin_hash) then
      return jsonb_build_object('ok', false, 'message', 'PIN incorreto.');
    end if;
    v_token := encode(extensions.gen_random_bytes(32), 'hex');
    insert into public.device_tokens (employee_id, device_id, token_hash, expires_at)
    values (v_employee.id, v_device_id, encode(extensions.digest(v_token, 'sha256'), 'hex'), now() + interval '72 hours');
  elsif not exists (
    select 1 from public.device_tokens
    where employee_id = v_employee.id and device_id = v_device_id
       and token_hash = encode(extensions.digest(coalesce(p_token, ''), 'sha256'), 'hex')
      and expires_at > now()
  ) then
    return jsonb_build_object('ok', false, 'message', 'Autorização offline expirada. Informe matrícula e PIN novamente.');
  else
    update public.device_tokens set last_used_at = now()
    where employee_id = v_employee.id and device_id = v_device_id
       and token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex');
    v_token := p_token;
  end if;

  v_effective_at := case when p_offline then p_captured_at else v_recorded_at end;
  select captured_at into v_latest_captured_at from public.punches
  where employee_id = v_employee.id and excluded_at is null
  order by captured_at desc limit 1;
  if v_latest_captured_at is not null and v_effective_at >= v_latest_captured_at
     and v_effective_at - v_latest_captured_at < interval '2 minutes' then
    return jsonb_build_object('ok', false, 'message', 'Batida repetida. Aguarde um instante e tente de novo.');
  end if;

  if p_channel = 'mobile' then
    select g.id,
      6371000 * 2 * asin(sqrt(
        power(sin(radians(p_latitude - g.latitude) / 2), 2) +
        cos(radians(p_latitude)) * cos(radians(g.latitude)) *
        power(sin(radians(p_longitude - g.longitude) / 2), 2)
      ))
    into v_geofence_id, v_distance
    from public.geofences g
    where g.active = true
    order by 6371000 * 2 * asin(sqrt(
      power(sin(radians(p_latitude - g.latitude) / 2), 2) +
      cos(radians(p_latitude)) * cos(radians(g.latitude)) *
      power(sin(radians(p_longitude - g.longitude) / 2), 2)
    )) asc
    limit 1;
    if v_geofence_id is not null then
      select v_distance <= radius_meters into v_inside from public.geofences where id = v_geofence_id;
    end if;
  end if;

  v_origin := case
    when p_channel = 'mobile' and p_offline then 'mobile_offline'
    when p_channel = 'kiosk' and p_offline then 'kiosk_offline'
    else p_channel
  end;
  select hash into v_previous_hash from public.punches order by created_at desc limit 1;
  v_previous_hash := coalesce(v_previous_hash, '');
  v_hash := encode(extensions.digest(
    p_client_record_id || '|' || v_employee.enrollment || '|' || v_effective_at::text || '|' || v_origin || '|' || v_previous_hash,
    'sha256'
  ), 'hex');

  insert into public.punches (
    client_record_id, employee_id, device_id, origin, captured_at, synced_at,
    latitude, longitude, accuracy_meters, geofence_id, inside_geofence, distance_meters,
    captured_offline, previous_hash, hash
  ) values (
    p_client_record_id, v_employee.id, v_device_id, v_origin, v_effective_at, now(),
    p_latitude, p_longitude, p_accuracy_meters, v_geofence_id, v_inside, v_distance,
    p_offline, v_previous_hash, v_hash
  );

  insert into public.audit_events (actor, action, entity, entity_id, details)
  values ('pwa', 'punch_registered', 'punch', p_client_record_id,
    jsonb_build_object('employee', v_employee.enrollment, 'origin', v_origin, 'offline', p_offline));

  return jsonb_build_object(
    'ok', true,
    'message', case when p_offline then 'Batida offline sincronizada, ' else 'Batida registrada, ' end || v_employee.name || ' — ' || to_char(v_effective_at at time zone 'America/Fortaleza', 'HH24:MI'),
    'token', v_token,
    'outside_geofence', coalesce(v_inside = false, false)
  );
end;
$$;

revoke all on function public.sync_punch from public, anon, authenticated;
grant execute on function public.sync_punch to service_role;
