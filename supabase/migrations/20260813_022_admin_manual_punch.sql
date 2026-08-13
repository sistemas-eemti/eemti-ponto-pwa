-- Manutenção de ponto: inclusão de batida manual (esquecimento) com ajuste
-- 'include', e listagem das batidas de um funcionário.

create or replace function public.admin_add_manual_punch(
  p_enrollment text,
  p_captured_at timestamptz,
  p_reason text default null
)
returns jsonb language plpgsql security definer set search_path = public, auth, extensions as $$
declare
  v_employee public.employees%rowtype;
  v_punch public.punches%rowtype;
  v_client_record_id text;
  v_previous_hash text := '';
  v_hash text;
  v_actor text := auth.jwt() ->> 'email';
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_enrollment, '')) = '' then
    raise exception 'Informe a matrícula ou CPF.';
  end if;
  if p_captured_at is null or p_captured_at > now() + interval '5 minutes' then
    raise exception 'Informe uma data e hora válidas.';
  end if;

  select * into v_employee from public.employees where enrollment = trim(p_enrollment);
  if not found then raise exception 'Funcionário não encontrado.'; end if;

  perform pg_advisory_xact_lock(186792024);

  v_client_record_id := 'MAN-' || replace(extensions.gen_random_uuid()::text, '-', '');
  select hash into v_previous_hash from public.punches order by created_at desc limit 1;
  v_previous_hash := coalesce(v_previous_hash, '');
  v_hash := encode(extensions.digest(
    v_client_record_id || '|' || v_employee.enrollment || '|' || p_captured_at::text || '|manual|' || v_previous_hash,
    'sha256'
  ), 'hex');

  insert into public.punches (
    client_record_id, employee_id, origin, captured_at, recorded_at, synced_at,
    captured_offline, previous_hash, hash
  ) values (
    v_client_record_id, v_employee.id, 'manual', p_captured_at, now(), now(),
    false, v_previous_hash, v_hash
  ) returning * into v_punch;

  insert into public.punch_adjustments (punch_id, kind, reason, after_value, requested_by, approved_by)
  values (v_punch.id, 'include',
          trim(coalesce(p_reason, 'Inclusão manual')),
          to_jsonb(v_punch),
          coalesce(v_actor, 'admin'), coalesce(v_actor, 'admin'));

  insert into public.audit_events (actor, action, entity, entity_id, details)
  values (coalesce(v_actor, 'admin'), 'punch_included_manual', 'punch', v_client_record_id,
    jsonb_build_object('employee', v_employee.enrollment));

  return jsonb_build_object('ok', true,
    'message', 'Batida manual incluída em ' ||
      to_char(p_captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') ||
      ' para ' || v_employee.name || '.');
end; $$;

create or replace function public.admin_list_employee_punches(p_enrollment text, p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_enrollment, '')) = '' then raise exception 'Informe a matrícula ou CPF.'; end if;
  if p_start is null or p_end is null then raise exception 'Informe o período.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.captured_at desc), '[]'::jsonb) into v_rows from (
    select p.id, e.enrollment, e.name,
           to_char(p.captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') as captured_at,
           p.origin, p.captured_offline, p.inside_geofence,
           round(p.distance_meters) as distance_meters,
           p.excluded_at is not null as excluded
    from public.punches p
    join public.employees e on e.id = p.employee_id
    where e.enrollment = trim(p_enrollment)
      and p.captured_at >= p_start::timestamptz
      and p.captured_at < (p_end + interval '1 day')::timestamptz
    order by p.captured_at desc
    limit 1000
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

revoke all on function
  public.admin_add_manual_punch(text, timestamptz, text),
  public.admin_list_employee_punches(text, date, date)
from public, anon;

grant execute on function
  public.admin_add_manual_punch(text, timestamptz, text),
  public.admin_list_employee_punches(text, date, date)
to authenticated;

select pg_notify('pgrst', 'reload schema');
