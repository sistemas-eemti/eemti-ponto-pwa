-- Campos adicionais do funcionário (paridade com o cadastro original do Admin).
-- Colunas novas + RPC de salvar/listar com todos os dados.

alter table public.employees
  add column if not exists sex text,
  add column if not exists birth_date date,
  add column if not exists salary numeric(12,2),
  add column if not exists barcode text,
  add column if not exists address text,
  add column if not exists neighborhood text,
  add column if not exists city text,
  add column if not exists cep text,
  add column if not exists phone text,
  add column if not exists mobile text;

drop function if exists public.admin_save_employee(text, text, text, uuid, uuid, uuid);

create or replace function public.admin_save_employee(
  p_enrollment text,
  p_name text,
  p_pin text default null,
  p_department_id uuid default null,
  p_position_id uuid default null,
  p_schedule_id uuid default null,
  p_cpf text default null,
  p_pis text default null,
  p_sex text default null,
  p_birth_date date default null,
  p_admission_date date default null,
  p_salary numeric default null,
  p_barcode text default null,
  p_address text default null,
  p_neighborhood text default null,
  p_city text default null,
  p_cep text default null,
  p_phone text default null,
  p_mobile text default null,
  p_active boolean default true
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

  insert into public.employees (
    enrollment, name, pin_hash, department_id, position_id, schedule_id,
    cpf, pis, sex, birth_date, admitted_on, salary, barcode,
    address, neighborhood, city, cep, phone, mobile
  ) values (
    trim(p_enrollment), trim(p_name),
    case when p_pin is not null and length(p_pin) >= 4
         then extensions.crypt(p_pin, extensions.gen_salt('bf')) else null end,
    p_department_id, p_position_id, p_schedule_id,
    nullif(p_cpf, ''), nullif(p_pis, ''), nullif(p_sex, ''),
    p_birth_date, p_admission_date, p_salary, nullif(p_barcode, ''),
    nullif(p_address, ''), nullif(p_neighborhood, ''), nullif(p_city, ''),
    nullif(p_cep, ''), nullif(p_phone, ''), nullif(p_mobile, '')
  )
  on conflict (enrollment) do update set
    name = excluded.name,
    pin_hash = coalesce(excluded.pin_hash, employees.pin_hash),
    department_id = excluded.department_id,
    position_id = excluded.position_id,
    schedule_id = excluded.schedule_id,
    cpf = excluded.cpf,
    pis = excluded.pis,
    sex = excluded.sex,
    birth_date = excluded.birth_date,
    admitted_on = excluded.admitted_on,
    salary = excluded.salary,
    barcode = excluded.barcode,
    address = excluded.address,
    neighborhood = excluded.neighborhood,
    city = excluded.city,
    cep = excluded.cep,
    phone = excluded.phone,
    mobile = excluded.mobile,
    active = coalesce(p_active, true)
  returning * into v_employee;

  insert into public.audit_events (actor, action, entity, entity_id, details)
  values (auth.uid()::text, 'employee_saved', 'employee', v_employee.id::text,
    jsonb_build_object('enrollment', v_employee.enrollment));

  return v_employee;
end;
$$;

create or replace function public.admin_list_employees()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select e.id, e.enrollment, e.name, e.active, e.department_id, e.position_id, e.schedule_id,
           e.cpf, e.pis, e.sex, e.birth_date, e.admitted_on, e.salary, e.barcode,
           e.address, e.neighborhood, e.city, e.cep, e.phone, e.mobile,
           d.name as department
    from public.employees e
    left join public.departments d on d.id = e.department_id
    where public.is_admin() order by e.name
  ) x;
$$;

revoke all on function public.admin_list_employees() from public, anon;
revoke all on function public.admin_save_employee(
  text, text, text, uuid, uuid, uuid, text, text, text, date, date, numeric,
  text, text, text, text, text, text, text, boolean
) from public, anon;

grant execute on function public.admin_list_employees() to authenticated;
grant execute on function public.admin_save_employee(
  text, text, text, uuid, uuid, uuid, text, text, text, date, date, numeric,
  text, text, text, text, text, text, text, boolean
) to authenticated;

select pg_notify('pgrst', 'reload schema');
