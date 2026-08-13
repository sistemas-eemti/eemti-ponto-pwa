-- Relatorios e monitor offline do Admin.
-- Horarios exibidos em America/Fortaleza.

create or replace function public.admin_espelho(p_enrollment text, p_month date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_rows jsonb;
  v_start timestamptz := (date_trunc('month', p_month) at time zone 'America/Fortaleza');
  v_end timestamptz := ((date_trunc('month', p_month) + interval '1 month') at time zone 'America/Fortaleza');
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.dia, x.entrada), '[]'::jsonb) into v_rows from (
    select e.enrollment, e.name,
           to_char(bd.entrada at time zone 'America/Fortaleza', 'DD/MM/YYYY') as dia,
           to_char(bd.entrada at time zone 'America/Fortaleza', 'HH24:MI') as entrada,
           to_char(bd.saida at time zone 'America/Fortaleza', 'HH24:MI') as saida,
           round(extract(epoch from (bd.saida - bd.entrada)) / 60)::int as minutos,
           bd.batidas
    from (
      select p.employee_id,
             (p.captured_at at time zone 'America/Fortaleza')::date as dia,
             min(p.captured_at) as entrada,
             max(p.captured_at) as saida,
             count(*) as batidas
      from public.punches p
      where p.captured_at >= v_start and p.captured_at < v_end and p.excluded_at is null
      group by p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date
    ) bd
    join public.employees e on e.id = bd.employee_id
    where e.enrollment = trim(p_enrollment)
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

create or replace function public.admin_resumo_mensal(p_month date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_rows jsonb;
  v_start timestamptz := (date_trunc('month', p_month) at time zone 'America/Fortaleza');
  v_end timestamptz := ((date_trunc('month', p_month) + interval '1 month') at time zone 'America/Fortaleza');
  v_dias_uteis integer;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;

  select count(*) into v_dias_uteis
  from generate_series(date_trunc('month', p_month)::date, (date_trunc('month', p_month) + interval '1 month' - interval '1 day')::date, interval '1 day') d(dia)
  where extract(isodow from d.dia) between 1 and 5
    and not exists (select 1 from public.holidays h where h.holiday_date = d.dia);

  with batidas_diarias as (
    select p.employee_id,
           (p.captured_at at time zone 'America/Fortaleza')::date as dia,
           min(p.captured_at) as entrada,
           max(p.captured_at) as saida
    from public.punches p
    where p.captured_at >= v_start and p.captured_at < v_end and p.excluded_at is null
    group by p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date
  ),
  resumo as (
    select e.enrollment, e.name, d.name as department, s.name as jornada,
           s.entry_time, s.tolerance_minutes, s.daily_minutes,
           count(bd.dia) as dias_trabalhados,
           count(*) filter (where s.entry_time is not null
             and (bd.entrada at time zone 'America/Fortaleza')::time > (s.entry_time + make_interval(mins => coalesce(s.tolerance_minutes, 0)))) as atrasos,
           coalesce(sum(extract(epoch from (bd.saida - bd.entrada)) / 60), 0)::int as minutos_trabalhados
    from public.employees e
    left join public.departments d on d.id = e.department_id
    left join public.schedules s on s.id = e.schedule_id
    left join batidas_diarias bd on bd.employee_id = e.id
    where e.active and public.is_admin()
    group by e.enrollment, e.name, d.name, s.name, s.entry_time, s.tolerance_minutes, s.daily_minutes
  )
  select coalesce(jsonb_agg(row_to_json(x) order by x.name), '[]'::jsonb) into v_rows
  from (
    select r.enrollment, r.name, r.department, r.jornada, r.dias_trabalhados,
           greatest(v_dias_uteis - r.dias_trabalhados, 0) as faltas,
           r.atrasos, r.minutos_trabalhados,
           coalesce(r.daily_minutes * v_dias_uteis, 0) as minutos_esperados,
           r.minutos_trabalhados - coalesce(r.daily_minutes * v_dias_uteis, 0) as saldo_minutos
    from resumo r
  ) x;

  return jsonb_build_object('dias_uteis', v_dias_uteis, 'rows', v_rows);
end; $$;

create or replace function public.admin_rel_atrasos(p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_start is null or p_end is null then raise exception 'Informe o período.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.dia, x.name), '[]'::jsonb) into v_rows from (
    select e.enrollment, e.name,
           to_char(s.entry_time, 'HH24:MI') as previsto,
           to_char(bd.entrada at time zone 'America/Fortaleza', 'DD/MM/YYYY') as dia,
           to_char(bd.entrada at time zone 'America/Fortaleza', 'HH24:MI') as batida,
           greatest(round(extract(epoch from ((bd.entrada at time zone 'America/Fortaleza')::time
             - (s.entry_time + make_interval(mins => coalesce(s.tolerance_minutes, 0))))) / 60)::int, 0) as atraso_min
    from (
      select p.employee_id,
             (p.captured_at at time zone 'America/Fortaleza')::date as dia,
             min(p.captured_at) as entrada
      from public.punches p
      where p.captured_at >= p_start::timestamptz
        and p.captured_at < (p_end + interval '1 day')::timestamptz
        and p.excluded_at is null
      group by p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date
    ) bd
    join public.employees e on e.id = bd.employee_id
    join public.schedules s on s.id = e.schedule_id
    where s.entry_time is not null
      and (bd.entrada at time zone 'America/Fortaleza')::time > (s.entry_time + make_interval(mins => coalesce(s.tolerance_minutes, 0)))
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

create or replace function public.admin_rel_faltas(p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_start is null or p_end is null then raise exception 'Informe o período.'; end if;
  with dias_uteis as (
    select d.dia from generate_series(p_start, p_end, interval '1 day') d(dia)
    where extract(isodow from d.dia) between 1 and 5
      and not exists (select 1 from public.holidays h where h.holiday_date = d.dia)
  ),
  batidas_diarias as (
    select p.employee_id,
           (p.captured_at at time zone 'America/Fortaleza')::date as dia
    from public.punches p
    where p.captured_at >= p_start::timestamptz
      and p.captured_at < (p_end + interval '1 day')::timestamptz
      and p.excluded_at is null
    group by p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date
  )
  select coalesce(jsonb_agg(row_to_json(x) order by x.name, x.dia), '[]'::jsonb) into v_rows from (
    select e.enrollment, e.name, to_char(d.dia, 'DD/MM/YYYY') as dia
    from public.employees e
    cross join dias_uteis d
    left join batidas_diarias bd on bd.employee_id = e.id and bd.dia = d.dia
    where e.active and public.is_admin() and bd.dia is null
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

create or replace function public.admin_monitor_offline()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.captured_at desc), '[]'::jsonb) into v_rows from (
    select e.enrollment, e.name, p.origin, p.captured_offline,
           p.captured_at, p.synced_at, p.client_record_id
    from public.punches p
    join public.employees e on e.id = p.employee_id
    where p.captured_offline and p.excluded_at is null
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

revoke all on function
  public.admin_espelho(text, date),
  public.admin_resumo_mensal(date),
  public.admin_rel_atrasos(date, date),
  public.admin_rel_faltas(date, date),
  public.admin_monitor_offline()
from public, anon;

grant execute on function
  public.admin_espelho(text, date),
  public.admin_resumo_mensal(date),
  public.admin_rel_atrasos(date, date),
  public.admin_rel_faltas(date, date),
  public.admin_monitor_offline()
to authenticated;

select pg_notify('pgrst', 'reload schema');
