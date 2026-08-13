-- Espelho detalhado: todas as batidas do mes, com jornada e intervalo.
-- Corrige o fuso horario (America/Fortaleza) no monitor offline e no dashboard.

create or replace function public.admin_espelho(p_enrollment text, p_month date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_rows jsonb;
  v_start timestamptz := (date_trunc('month', p_month) at time zone 'America/Fortaleza');
  v_end timestamptz := ((date_trunc('month', p_month) + interval '1 month') at time zone 'America/Fortaleza');
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.dia, x.hora), '[]'::jsonb) into v_rows from (
    select e.enrollment, e.name,
           to_char(p.captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY') as dia,
           to_char(p.captured_at at time zone 'America/Fortaleza', 'HH24:MI:SS') as hora,
           to_char(s.entry_time, 'HH24:MI') as entrada_prevista,
           to_char(s.exit_time, 'HH24:MI') as saida_prevista,
           case when s.break_start is null or s.break_end is null then '-'
                else to_char(s.break_start, 'HH24:MI') || ' - ' || to_char(s.break_end, 'HH24:MI') end as intervalo,
           p.origin,
           p.captured_offline,
           case when p.inside_geofence is null then '-' when p.inside_geofence then 'Dentro' else 'Fora' end as cerca
    from public.punches p
    join public.employees e on e.id = p.employee_id
    left join public.schedules s on s.id = e.schedule_id
    where e.enrollment = trim(p_enrollment)
      and p.captured_at >= v_start and p.captured_at < v_end
      and p.excluded_at is null
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
           to_char(p.captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') as captured_at,
           to_char(p.synced_at at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') as synced_at,
           p.client_record_id
    from public.punches p
    join public.employees e on e.id = p.employee_id
    where p.captured_offline and p.excluded_at is null
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

create or replace function public.admin_dashboard()
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare
  v_today timestamptz := date_trunc('day', now() at time zone 'America/Fortaleza') at time zone 'America/Fortaleza';
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  return jsonb_build_object(
    'employees', (select count(*) from public.employees where active),
    'punches', (select count(*) from public.punches where captured_at >= v_today),
    'outside', (select count(*) from public.punches where captured_at >= v_today and inside_geofence = false),
    'geofences', (select count(*) from public.geofences where active),
    'recent', coalesce((select jsonb_agg(row_to_json(x)) from (
      select to_char(p.captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') as captured_at,
             p.origin, p.inside_geofence, e.name, e.enrollment
      from public.punches p join public.employees e on e.id = p.employee_id
      order by p.captured_at desc limit 12
    ) x), '[]'::jsonb)
  );
end; $$;

revoke all on function public.admin_espelho(text, date), public.admin_monitor_offline(), public.admin_dashboard() from public, anon;
grant execute on function public.admin_espelho(text, date), public.admin_monitor_offline(), public.admin_dashboard() to authenticated;

select pg_notify('pgrst', 'reload schema');
