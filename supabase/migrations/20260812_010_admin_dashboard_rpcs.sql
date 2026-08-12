-- API administrativa para o navegador. O acesso a tabelas permanece restrito
-- e cada operacao confirma o perfil admin antes de retornar ou alterar dados.

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
      select p.captured_at, p.origin, p.inside_geofence, e.name, e.enrollment
      from public.punches p join public.employees e on e.id = p.employee_id
      order by p.captured_at desc limit 12
    ) x), '[]'::jsonb)
  );
end; $$;

create or replace function public.admin_list_employees()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select e.enrollment, e.name, e.active, d.name as department
    from public.employees e left join public.departments d on d.id = e.department_id
    where public.is_admin() order by e.name
  ) x;
$$;

create or replace function public.admin_employee_options()
returns jsonb language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  return jsonb_build_object(
    'departments', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (select id, name from public.departments order by name) x),
    'positions', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (select id, name from public.positions order by name) x),
    'schedules', (select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (select id, name from public.schedules order by name) x)
  );
end; $$;

create or replace function public.admin_list_geofences()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select id, name, latitude, longitude, radius_meters, active
    from public.geofences where public.is_admin() order by name
  ) x;
$$;

create or replace function public.admin_create_geofence(p_name text, p_latitude numeric, p_longitude numeric, p_radius_meters integer)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  insert into public.geofences (name, latitude, longitude, radius_meters)
  values (trim(p_name), p_latitude, p_longitude, p_radius_meters);
end; $$;

revoke all on function public.admin_dashboard() from public, anon;
revoke all on function public.admin_list_employees() from public, anon;
revoke all on function public.admin_employee_options() from public, anon;
revoke all on function public.admin_list_geofences() from public, anon;
revoke all on function public.admin_create_geofence(text, numeric, numeric, integer) from public, anon;
grant execute on function public.admin_dashboard(), public.admin_list_employees(), public.admin_employee_options(), public.admin_list_geofences() to authenticated;
grant execute on function public.admin_create_geofence(text, numeric, numeric, integer) to authenticated;

select pg_notify('pgrst', 'reload schema');
