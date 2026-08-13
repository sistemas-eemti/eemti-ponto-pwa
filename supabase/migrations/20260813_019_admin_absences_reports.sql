-- Gestao de ausencias (faltas/atestados/ferias/folgas) e relatorios completos
-- de atrasos e faltas, no estilo do app antigo (abonadas, resumo por funcionario).

create or replace function public.admin_list_absences(p_start date, p_end date)
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x) order by x.absence_date desc), '[]'::jsonb) from (
    select a.id, e.enrollment, e.name,
           to_char(a.absence_date, 'DD/MM/YYYY') as absence_date,
           a.type, a.reason, a.excused, a.document_reference
    from public.absences a
    join public.employees e on e.id = a.employee_id
    where a.absence_date between p_start and p_end
      and public.is_admin()
  ) x;
$$;

create or replace function public.admin_save_absence(
  p_id uuid default null,
  p_enrollment text,
  p_date date,
  p_type text,
  p_reason text default null,
  p_excused boolean default false
)
returns void language plpgsql security definer set search_path = public as $$
declare v_employee_id uuid;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_enrollment, '')) = '' or p_date is null then
    raise exception 'Matrícula e data são obrigatórias.';
  end if;
  if p_type not in ('falta', 'atestado', 'férias', 'ferias', 'folga') then
    raise exception 'Tipo de ausência inválido.';
  end if;
  select id into v_employee_id from public.employees where enrollment = trim(p_enrollment);
  if v_employee_id is null then raise exception 'Funcionário não encontrado.'; end if;

  if p_id is null then
    insert into public.absences (employee_id, absence_date, type, reason, excused, document_reference)
    values (v_employee_id, p_date, case when p_type = 'ferias' then 'férias' else p_type end,
            nullif(trim(coalesce(p_reason, '')), ''), coalesce(p_excused, false), null)
    on conflict (employee_id, absence_date, type) do update set
      reason = excluded.reason, excused = excluded.excused, document_reference = excluded.document_reference;
  else
    update public.absences set
      employee_id = v_employee_id,
      absence_date = p_date,
      type = case when p_type = 'ferias' then 'férias' else p_type end,
      reason = nullif(trim(coalesce(p_reason, '')), ''),
      excused = coalesce(p_excused, false)
    where id = p_id;
  end if;
end; $$;

create or replace function public.admin_delete_absence(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  delete from public.absences where id = p_id;
end; $$;

create or replace function public.admin_rel_atrasos(p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_resumo jsonb;
  v_por_funcionario jsonb;
  v_lista jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_start is null or p_end is null then raise exception 'Informe o período.'; end if;

  with diarias as (
    select p.employee_id,
           (p.captured_at at time zone 'America/Fortaleza')::date as dia,
           min(p.captured_at) as entrada
    from public.punches p
    where p.captured_at >= p_start::timestamptz
      and p.captured_at < (p_end + interval '1 day')::timestamptz
      and p.excluded_at is null
    group by p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date
  ),
  atrasos as (
    select e.enrollment, e.name, coalesce(dpt.name, '') as department,
           to_char(s.entry_time, 'HH24:MI') as previsto,
           to_char(d.dia, 'DD/MM/YYYY') as dia,
           to_char(d.entrada at time zone 'America/Fortaleza', 'HH24:MI') as batida,
           greatest(round(extract(epoch from ((d.entrada at time zone 'America/Fortaleza')::time
             - (s.entry_time + make_interval(mins => coalesce(s.tolerance_minutes, 0))))) / 60)::int, 0) as atraso_min
    from diarias d
    join public.employees e on e.id = d.employee_id
    left join public.departments dpt on dpt.id = e.department_id
    left join public.schedules s on s.id = e.schedule_id
    where s.entry_time is not null
      and (d.entrada at time zone 'America/Fortaleza')::time > (s.entry_time + make_interval(mins => coalesce(s.tolerance_minutes, 0)))
  )
  select jsonb_build_object(
           'funcionarios_com_atraso', count(distinct enrollment),
           'total_atrasos', count(*),
           'total_minutos', coalesce(sum(atraso_min), 0))
  into v_resumo from atrasos;

  select coalesce(jsonb_agg(row_to_json(x) order by x.minutos_atraso desc), '[]'::jsonb) into v_por_funcionario from (
    select enrollment, name, department, count(*) as atrasos, sum(atraso_min) as minutos_atraso
    from atrasos group by enrollment, name, department
  ) x;

  select coalesce(jsonb_agg(row_to_json(x) order by x.dia, x.name), '[]'::jsonb) into v_lista from (
    select enrollment, name, previsto, dia, batida, atraso_min from atrasos
  ) x;

  return jsonb_build_object('resumo', v_resumo, 'por_funcionario', v_por_funcionario, 'lista', v_lista);
end; $$;

create or replace function public.admin_rel_faltas(p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_resumo jsonb;
  v_por_funcionario jsonb;
  v_lista jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_start is null or p_end is null then raise exception 'Informe o período.'; end if;

  with dias_uteis as (
    select d.dia from generate_series(p_start, p_end, interval '1 day') d(dia)
    where extract(isodow from d.dia) between 1 and 5
      and not exists (select 1 from public.holidays h where h.holiday_date = d.dia)
  ),
  batidas_diarias as (
    select p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date as dia
    from public.punches p
    where p.captured_at >= p_start::timestamptz
      and p.captured_at < (p_end + interval '1 day')::timestamptz
      and p.excluded_at is null
    group by p.employee_id, (p.captured_at at time zone 'America/Fortaleza')::date
  ),
  automaticas as (
    select e.enrollment, e.name, d.dia, 'falta'::text as tipo, false as excused, ''::text as reason, true as automatica
    from public.employees e
    cross join dias_uteis d
    left join batidas_diarias bd on bd.employee_id = e.id and bd.dia = d.dia
    left join public.absences a on a.employee_id = e.id and a.absence_date = d.dia
    where e.active and public.is_admin() and bd.dia is null and a.id is null
  ),
  registradas as (
    select e.enrollment, e.name, a.absence_date as dia, a.type, a.excused, coalesce(a.reason, '') as reason, false as automatica
    from public.absences a
    join public.employees e on e.id = a.employee_id
    where a.absence_date between p_start and p_end and public.is_admin()
  ),
  todas as (select * from automaticas union all select * from registradas)
  select jsonb_build_object(
           'total_faltas', count(*),
           'abonadas', count(*) filter (where excused),
           'nao_abonadas', count(*) filter (where not excused),
           'funcionarios', count(distinct enrollment))
  into v_resumo from todas;

  select coalesce(jsonb_agg(row_to_json(x) order by x.nao_abonadas desc), '[]'::jsonb) into v_por_funcionario from (
    select enrollment, name,
           count(*) as total,
           count(*) filter (where excused) as abonadas,
           count(*) filter (where not excused) as nao_abonadas
    from todas group by enrollment, name
  ) x;

  select coalesce(jsonb_agg(row_to_json(x) order by x.dia desc, x.name), '[]'::jsonb) into v_lista from (
    select enrollment, name, to_char(dia, 'DD/MM/YYYY') as dia, tipo, excused, reason, automatica from todas
  ) x;

  return jsonb_build_object('resumo', v_resumo, 'por_funcionario', v_por_funcionario, 'lista', v_lista);
end; $$;

revoke all on function
  public.admin_list_absences(date, date),
  public.admin_save_absence(uuid, text, date, text, text, boolean),
  public.admin_delete_absence(uuid),
  public.admin_rel_atrasos(date, date),
  public.admin_rel_faltas(date, date)
from public, anon;

grant execute on function
  public.admin_list_absences(date, date),
  public.admin_save_absence(uuid, text, date, text, text, boolean),
  public.admin_delete_absence(uuid),
  public.admin_rel_atrasos(date, date),
  public.admin_rel_faltas(date, date)
to authenticated;

select pg_notify('pgrst', 'reload schema');
