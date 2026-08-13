-- Relatorios: batidas fora da cerca e assiduidade por funcionario.
-- No estilo do app antigo (KPIs + resumo por funcionario + detalhado).

create or replace function public.admin_rel_fora_cerca(p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_resumo jsonb;
  v_por_funcionario jsonb;
  v_lista jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_start is null or p_end is null then raise exception 'Informe o período.'; end if;

  with fora as (
    select e.enrollment, e.name, p.origin, p.distance_meters, p.captured_at
    from public.punches p
    join public.employees e on e.id = p.employee_id
    where p.inside_geofence = false
      and p.captured_at >= p_start::timestamptz
      and p.captured_at < (p_end + interval '1 day')::timestamptz
      and p.excluded_at is null
  )
  select jsonb_build_object(
           'total_batidas', count(*),
           'funcionarios_envolvidos', count(distinct enrollment))
  into v_resumo from fora;

  select coalesce(jsonb_agg(row_to_json(x) order by x.total desc), '[]'::jsonb) into v_por_funcionario from (
    select enrollment, name, count(*) as total from fora group by enrollment, name
  ) x;

  select coalesce(jsonb_agg(row_to_json(x) order by x.captured_at desc), '[]'::jsonb) into v_lista from (
    select enrollment, name,
           to_char(captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY') as dia,
           to_char(captured_at at time zone 'America/Fortaleza', 'HH24:MI') as hora,
           origin, distance_meters
    from fora
  ) x;

  return jsonb_build_object('resumo', v_resumo, 'por_funcionario', v_por_funcionario, 'lista', v_lista);
end; $$;

create or replace function public.admin_assiduidade(p_enrollment text, p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_result jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_enrollment, '')) = '' or p_start is null or p_end is null then
    raise exception 'Informe matrícula e período.';
  end if;

  with dias_uteis as (
    select count(*) as total from generate_series(p_start, p_end, interval '1 day') d(dia)
    where extract(isodow from d.dia) between 1 and 5
      and not exists (select 1 from public.holidays h where h.holiday_date = d.dia)
  ),
  diarias as (
    select p.employee_id,
           (p.captured_at at time zone 'America/Fortaleza')::date as dia,
           min(p.captured_at) as entrada,
           max(p.captured_at) as saida
    from public.punches p
    where p.captured_at >= p_start::timestamptz
      and p.captured_at < (p_end + interval '1 day')::timestamptz
      and p.excluded_at is null
    group by p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date
  ),
  base as (
    select e.enrollment, e.name, s.name as jornada,
           s.entry_time, s.tolerance_minutes, s.daily_minutes,
           (select total from dias_uteis) as dias_uteis,
           count(d.dia) as dias_trabalhados,
           count(*) filter (where s.entry_time is not null
             and (d.entrada at time zone 'America/Fortaleza')::time > (s.entry_time + make_interval(mins => coalesce(s.tolerance_minutes, 0)))) as atrasos,
           coalesce(sum(extract(epoch from (d.saida - d.entrada)) / 60), 0)::int as minutos_trabalhados
    from public.employees e
    left join public.schedules s on s.id = e.schedule_id
    left join diarias d on d.employee_id = e.id
    where e.enrollment = trim(p_enrollment)
    group by e.enrollment, e.name, s.name, s.entry_time, s.tolerance_minutes, s.daily_minutes
  )
  select jsonb_build_object(
    'enrollment', base.enrollment,
    'name', base.name,
    'jornada', base.jornada,
    'dias_uteis', base.dias_uteis,
    'dias_trabalhados', base.dias_trabalhados,
    'faltas', greatest(base.dias_uteis - base.dias_trabalhados, 0),
    'atrasos', base.atrasos,
    'total_min', base.minutos_trabalhados,
    'esperado_min', coalesce(base.daily_minutes * base.dias_uteis, 0),
    'saldo_min', base.minutos_trabalhados - coalesce(base.daily_minutes * base.dias_uteis, 0)
  ) into v_result from base;

  return coalesce(v_result, jsonb_build_object(
    'enrollment', trim(p_enrollment), 'name', 'Funcionário não encontrado',
    'jornada', null, 'dias_uteis', 0, 'dias_trabalhados', 0, 'faltas', 0,
    'atrasos', 0, 'total_min', 0, 'esperado_min', 0, 'saldo_min', 0));
end; $$;

revoke all on function public.admin_rel_fora_cerca(date, date), public.admin_assiduidade(text, date, date) from public, anon;
grant execute on function public.admin_rel_fora_cerca(date, date), public.admin_assiduidade(text, date, date) to authenticated;

select pg_notify('pgrst', 'reload schema');
