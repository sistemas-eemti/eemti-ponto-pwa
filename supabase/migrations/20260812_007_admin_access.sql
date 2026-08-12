-- Vincula o primeiro administrador a uma conta existente do Supabase Auth.
-- Crie primeiro sistemas.eemti@gmail.com em Authentication > Users.

create table public.admin_profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'operator')),
  display_name text,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger admin_profiles_updated_at before update on public.admin_profiles
for each row execute function public.set_updated_at();

alter table public.admin_profiles enable row level security;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select exists (
    select 1 from public.admin_profiles
    where user_id = auth.uid() and role = 'admin' and active
  );
$$;

grant execute on function public.is_admin() to authenticated;

create policy "admin can read own profile" on public.admin_profiles
for select to authenticated using (user_id = auth.uid());

do $$
declare
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where email = 'sistemas.eemti@gmail.com';
  if v_user_id is null then
    raise exception 'Crie primeiro a conta sistemas.eemti@gmail.com em Authentication > Users.';
  end if;

  insert into public.admin_profiles (user_id, role, display_name)
  values (v_user_id, 'admin', 'Administração EEMTI')
  on conflict (user_id) do update set role = excluded.role, active = true;
end;
$$;

-- O Admin autenticado acessa dados exclusivamente pelas politicas abaixo.
create policy "admin manage departments" on public.departments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage positions" on public.positions for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage schedules" on public.schedules for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage employees" on public.employees for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage geofences" on public.geofences for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin read devices" on public.devices for select to authenticated using (public.is_admin());
create policy "admin read tokens" on public.device_tokens for select to authenticated using (public.is_admin());
create policy "admin manage punches" on public.punches for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage adjustments" on public.punch_adjustments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage absences" on public.absences for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage occurrences" on public.occurrences for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin manage holidays" on public.holidays for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "admin read audit events" on public.audit_events for select to authenticated using (public.is_admin());
create policy "admin manage settings" on public.settings for all to authenticated using (public.is_admin()) with check (public.is_admin());
