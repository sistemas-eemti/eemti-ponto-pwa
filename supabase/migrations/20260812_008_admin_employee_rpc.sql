-- Cadastro de funcionário com PIN processado exclusivamente no banco.

create or replace function public.admin_save_employee(
  p_enrollment text,
  p_name text,
  p_pin text,
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
begin
  if not public.is_admin() then
    raise exception 'Acesso administrativo negado.';
  end if;
  if trim(coalesce(p_enrollment, '')) = '' or trim(coalesce(p_name, '')) = '' then
    raise exception 'Matrícula e nome são obrigatórios.';
  end if;
  if length(coalesce(p_pin, '')) < 4 then
    raise exception 'O PIN deve ter ao menos 4 caracteres.';
  end if;

  insert into public.employees (
    enrollment, name, pin_hash, department_id, position_id, schedule_id
  ) values (
    trim(p_enrollment), trim(p_name), extensions.crypt(p_pin, extensions.gen_salt('bf')),
    p_department_id, p_position_id, p_schedule_id
  )
  on conflict (enrollment) do update set
    name = excluded.name,
    pin_hash = excluded.pin_hash,
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

revoke all on function public.admin_save_employee(text, text, text, uuid, uuid, uuid) from public, anon;
grant execute on function public.admin_save_employee(text, text, text, uuid, uuid, uuid) to authenticated;
