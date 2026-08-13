-- Ocorrencias, motivos (reasons), opcoes/parametros (settings) no estilo do
-- app antigo; resumo mensal com bloco "por departamento"; mensagem ao
-- funcionario (aviso) retornada na sincronizacao da batida.

create table if not exists public.reasons (
  id uuid primary key default gen_random_uuid(),
  description text not null,
  category text not null check (category in ('ajuste', 'falta', 'abono')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger reasons_updated_at before update on public.reasons
for each row execute function public.set_updated_at();

alter table public.reasons enable row level security;

create policy "admin manage reasons" on public.reasons for all to authenticated using (public.is_admin()) with check (public.is_admin());

-- Ocorrencias -------------------------------------------------------------

create or replace function public.admin_list_occurrences(p_start date, p_end date)
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x) order by x.occurrence_date desc, x.created_at desc), '[]'::jsonb) from (
    select o.id, e.enrollment, e.name,
           to_char(o.occurrence_date, 'DD/MM/YYYY') as occurrence_date,
           o.type, o.description, o.recorded_by, o.created_at
    from public.occurrences o
    join public.employees e on e.id = o.employee_id
    where o.occurrence_date between p_start and p_end
      and public.is_admin()
  ) x;
$$;

create or replace function public.admin_save_occurrence(
  p_id uuid default null,
  p_enrollment text default null,
  p_date date default null,
  p_type text default null,
  p_description text default null
)
returns void language plpgsql security definer set search_path = public, auth as $$
declare v_employee_id uuid;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_enrollment, '')) = '' or p_date is null then
    raise exception 'Matrícula e data são obrigatórias.';
  end if;
  if trim(coalesce(p_description, '')) = '' then
    raise exception 'Descrição é obrigatória.';
  end if;
  select id into v_employee_id from public.employees where enrollment = trim(p_enrollment);
  if v_employee_id is null then raise exception 'Funcionário não encontrado.'; end if;

  if p_id is null then
    insert into public.occurrences (employee_id, occurrence_date, type, description, recorded_by)
    values (v_employee_id, p_date, coalesce(nullif(trim(p_type), ''), 'geral'),
            trim(p_description), coalesce(auth.jwt()->>'email', 'admin'));
  else
    update public.occurrences set
      employee_id = v_employee_id,
      occurrence_date = p_date,
      type = coalesce(nullif(trim(p_type), ''), 'geral'),
      description = trim(p_description)
    where id = p_id;
  end if;
end; $$;

create or replace function public.admin_delete_occurrence(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  delete from public.occurrences where id = p_id;
end; $$;

-- Motivos (reasons) -------------------------------------------------------

create or replace function public.admin_list_reasons()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x) order by x.category, x.description), '[]'::jsonb) from (
    select id, description, category, active
    from public.reasons
    where public.is_admin()
  ) x;
$$;

create or replace function public.admin_save_reason(
  p_id uuid default null,
  p_description text default null,
  p_category text default 'ajuste',
  p_active boolean default true
)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_description, '')) = '' then
    raise exception 'Informe a descrição.';
  end if;
  if p_category not in ('ajuste', 'falta', 'abono') then
    raise exception 'Categoria inválida.';
  end if;
  if p_id is null then
    insert into public.reasons (description, category, active)
    values (trim(p_description), p_category, coalesce(p_active, true));
  else
    update public.reasons set
      description = trim(p_description),
      category = p_category,
      active = coalesce(p_active, true)
    where id = p_id;
  end if;
end; $$;

create or replace function public.admin_delete_reason(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  delete from public.reasons where id = p_id;
end; $$;

-- Opções / parâmetros (settings) -----------------------------------------

create or replace function public.admin_list_settings()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x) order by x.key), '[]'::jsonb) from (
    select key, value #>> '{}' as value, to_char(updated_at, 'DD/MM/YYYY HH24:MI') as updated_at
    from public.settings
    where public.is_admin()
  ) x;
$$;

create or replace function public.admin_save_setting(p_key text, p_value text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_key not in ('mensagem_funcionario', 'tolerancia_padrao', 'email_alertas') then
    raise exception 'Parâmetro não permitido.';
  end if;
  insert into public.settings (key, value, updated_at)
  values (p_key, to_jsonb(coalesce(trim(p_value), '')), now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end; $$;

-- Resumo mensal com bloco "por departamento" ------------------------------

create or replace function public.admin_resumo_mensal(p_month date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_dias_uteis integer;
  v_result jsonb;
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
    where p.captured_at >= (date_trunc('month', p_month) at time zone 'America/Fortaleza')
      and p.captured_at < ((date_trunc('month', p_month) + interval '1 month') at time zone 'America/Fortaleza')
      and p.excluded_at is null
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
  select jsonb_build_object(
    'dias_uteis', v_dias_uteis,
    'rows', coalesce((select jsonb_agg(row_to_json(f)) from (
      select r.enrollment, r.name, r.department, r.jornada, r.dias_trabalhados,
             greatest(v_dias_uteis - r.dias_trabalhados, 0) as faltas,
             r.atrasos, r.minutos_trabalhados,
             coalesce(r.daily_minutes * v_dias_uteis, 0) as minutos_esperados,
             r.minutos_trabalhados - coalesce(r.daily_minutes * v_dias_uteis, 0) as saldo_minutos
      from resumo r order by r.name
    ) f), '[]'::jsonb),
    'departamentos', coalesce((select jsonb_agg(row_to_json(g) order by g.nome) from (
      select coalesce(department, 'Sem departamento') as nome,
             count(*) as funcionarios,
             sum(minutos_trabalhados) as trabalhado_min,
             sum(coalesce(daily_minutes * v_dias_uteis, 0)) as esperado_min,
             sum(minutos_trabalhados) - sum(coalesce(daily_minutes * v_dias_uteis, 0)) as saldo_min
      from resumo group by department
    ) g), '[]'::jsonb)
  ) into v_result;

  return v_result;
end; $$;

-- Mensagem ao funcionário no retorno da batida ----------------------------

create or replace function public.sync_punch_api(p_payload jsonb)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_result jsonb;
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
    v_result := jsonb_set(v_result, '{aviso}',
      to_jsonb((select value #>> '{}' from public.settings where key = 'mensagem_funcionario')),
      true);
  end if;
  return v_result;
end;
$$;

revoke all on function
  public.admin_list_occurrences(date, date),
  public.admin_save_occurrence(uuid, text, date, text, text),
  public.admin_delete_occurrence(uuid),
  public.admin_list_reasons(),
  public.admin_save_reason(uuid, text, text, boolean),
  public.admin_delete_reason(uuid),
  public.admin_list_settings(),
  public.admin_save_setting(text, text),
  public.admin_resumo_mensal(date),
  public.sync_punch_api(jsonb)
from public, anon;

grant execute on function
  public.admin_list_occurrences(date, date),
  public.admin_save_occurrence(uuid, text, date, text, text),
  public.admin_delete_occurrence(uuid),
  public.admin_list_reasons(),
  public.admin_save_reason(uuid, text, text, boolean),
  public.admin_delete_reason(uuid),
  public.admin_list_settings(),
  public.admin_save_setting(text, text),
  public.admin_resumo_mensal(date)
to authenticated;

grant execute on function public.sync_punch_api(jsonb) to service_role;

select pg_notify('pgrst', 'reload schema');
