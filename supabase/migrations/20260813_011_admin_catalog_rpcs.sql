-- Gestao de departamentos, cargos e jornadas pelo Admin.
-- Todas as operacoes confirmam perfil admin e protegem o PIN dos funcionarios.

create or replace function public.admin_list_employees()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select e.id, e.enrollment, e.name, e.active, d.name as department
    from public.employees e left join public.departments d on d.id = e.department_id
    where public.is_admin() order by e.name
  ) x;
$$;

create or replace function public.admin_list_departments()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select d.id, d.name, count(e.id) as employees
    from public.departments d left join public.employees e on e.department_id = d.id
    where public.is_admin() group by d.id order by d.name
  ) x;
$$;

create or replace function public.admin_save_department(p_id uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Informe o nome do departamento.'; end if;
  if p_id is null then
    insert into public.departments (name) values (trim(p_name));
  else
    update public.departments set name = trim(p_name) where id = p_id;
  end if;
end; $$;

create or replace function public.admin_delete_department(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if exists (select 1 from public.employees where department_id = p_id) then
    raise exception 'Há funcionários vinculados a este departamento.';
  end if;
  delete from public.departments where id = p_id;
end; $$;

create or replace function public.admin_list_positions()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select p.id, p.name, count(e.id) as employees
    from public.positions p left join public.employees e on e.position_id = p.id
    where public.is_admin() group by p.id order by p.name
  ) x;
$$;

create or replace function public.admin_save_position(p_id uuid, p_name text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Informe o nome do cargo.'; end if;
  if p_id is null then
    insert into public.positions (name) values (trim(p_name));
  else
    update public.positions set name = trim(p_name) where id = p_id;
  end if;
end; $$;

create or replace function public.admin_delete_position(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if exists (select 1 from public.employees where position_id = p_id) then
    raise exception 'Há funcionários vinculados a este cargo.';
  end if;
  delete from public.positions where id = p_id;
end; $$;

create or replace function public.admin_list_schedules()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select s.id, s.name, s.entry_time, s.exit_time, s.daily_minutes, s.tolerance_minutes, s.active, count(e.id) as employees
    from public.schedules s left join public.employees e on e.schedule_id = s.id
    where public.is_admin() group by s.id order by s.name
  ) x;
$$;

create or replace function public.admin_save_schedule(
  p_id uuid, p_name text, p_entry_time text, p_exit_time text,
  p_daily_minutes integer, p_tolerance_minutes integer
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_entry time := nullif(p_entry_time, '')::time;
  v_exit time := nullif(p_exit_time, '')::time;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Informe o nome da jornada.'; end if;
  if coalesce(p_daily_minutes, 0) < 0 then raise exception 'Carga diária inválida.'; end if;
  if coalesce(p_tolerance_minutes, 0) < 0 then raise exception 'Tolerância inválida.'; end if;
  if p_id is null then
    insert into public.schedules (name, entry_time, exit_time, daily_minutes, tolerance_minutes)
    values (trim(p_name), v_entry, v_exit, coalesce(p_daily_minutes, 0), coalesce(p_tolerance_minutes, 0));
  else
    update public.schedules set
      name = trim(p_name), entry_time = v_entry, exit_time = v_exit,
      daily_minutes = coalesce(p_daily_minutes, 0), tolerance_minutes = coalesce(p_tolerance_minutes, 0)
    where id = p_id;
  end if;
end; $$;

create or replace function public.admin_delete_schedule(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if exists (select 1 from public.employees where schedule_id = p_id) then
    raise exception 'Há funcionários vinculados a esta jornada.';
  end if;
  delete from public.schedules where id = p_id;
end; $$;

create or replace function public.admin_set_employee_active(p_enrollment text, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  update public.employees set active = p_active where enrollment = trim(p_enrollment);
  if not found then raise exception 'Funcionário não encontrado.'; end if;
end; $$;

revoke all on function
  public.admin_list_departments(),
  public.admin_save_department(uuid, text),
  public.admin_delete_department(uuid),
  public.admin_list_positions(),
  public.admin_save_position(uuid, text),
  public.admin_delete_position(uuid),
  public.admin_list_schedules(),
  public.admin_save_schedule(uuid, text, text, text, integer, integer),
  public.admin_delete_schedule(uuid),
  public.admin_set_employee_active(text, boolean)
from public, anon;

grant execute on function
  public.admin_list_departments(),
  public.admin_save_department(uuid, text),
  public.admin_delete_department(uuid),
  public.admin_list_positions(),
  public.admin_save_position(uuid, text),
  public.admin_delete_position(uuid),
  public.admin_list_schedules(),
  public.admin_save_schedule(uuid, text, text, text, integer, integer),
  public.admin_delete_schedule(uuid),
  public.admin_set_employee_active(text, boolean)
to authenticated;

select pg_notify('pgrst', 'reload schema');
