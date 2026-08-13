-- Geocercas: ativar/inativar e excluir pelo Admin.
-- Funcionarios: edicao com PIN opcional (mantem o PIN atual se vazio).

create or replace function public.admin_set_geofence_active(p_id uuid, p_active boolean)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  update public.geofences set active = coalesce(p_active, true) where id = p_id;
  if not found then raise exception 'Geocerca não encontrada.'; end if;
end; $$;

create or replace function public.admin_delete_geofence(p_id uuid)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  delete from public.geofences where id = p_id;
end; $$;

create or replace function public.admin_list_employees()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select e.id, e.enrollment, e.name, e.active, e.department_id, e.position_id, e.schedule_id,
           d.name as department
    from public.employees e
    left join public.departments d on d.id = e.department_id
    where public.is_admin() order by e.name
  ) x;
$$;

create or replace function public.admin_save_employee(
  p_enrollment text,
  p_name text,
  p_pin text default null,
  p_department_id uuid default null,
  p_position_id uuid default null,
  p_schedule_id uuid default null
)
returns public.employees
language plpgsql
security definer
set search_path = public, extensions, auth
as $$
declare
  v_employee public.employees;
  v_exists boolean;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_enrollment, '')) = '' or trim(coalesce(p_name, '')) = '' then
    raise exception 'Matrícula e nome são obrigatórios.';
  end if;

  select exists (select 1 from public.employees where enrollment = trim(p_enrollment)) into v_exists;
  if not v_exists and length(coalesce(p_pin, '')) < 4 then
    raise exception 'O PIN deve ter ao menos 4 caracteres.';
  end if;

  insert into public.employees (enrollment, name, pin_hash, department_id, position_id, schedule_id)
  values (
    trim(p_enrollment), trim(p_name),
    case when p_pin is not null and length(p_pin) >= 4
         then extensions.crypt(p_pin, extensions.gen_salt('bf')) else null end,
    p_department_id, p_position_id, p_schedule_id
  )
  on conflict (enrollment) do update set
    name = excluded.name,
    pin_hash = coalesce(excluded.pin_hash, employees.pin_hash),
    department_id = excluded.department_id,
    position_id = excluded.position_id,
    schedule_id = excluded.schedule_id,
    active = true
  returning * into v_employee;

  insert into public.audit_events (actor, action, entity, entity_id, details)
  values (auth.uid()::text, 'employee_saved', 'employee', v_employee.id::text,
    jsonb_build_object('enrollment', v_employee.enrollment));

  return v_employee;
end;
$$;

revoke all on function public.admin_set_geofence_active(uuid, boolean), public.admin_delete_geofence(uuid) from public, anon;
grant execute on function public.admin_set_geofence_active(uuid, boolean), public.admin_delete_geofence(uuid) to authenticated;
grant execute on function public.admin_save_employee(text, text, text, uuid, uuid, uuid), public.admin_list_employees() to authenticated;

select pg_notify('pgrst', 'reload schema');
