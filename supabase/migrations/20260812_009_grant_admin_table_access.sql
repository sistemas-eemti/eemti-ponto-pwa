-- RLS define quais linhas o administrador pode acessar. Estes grants permitem
-- que usuarios autenticados cheguem as tabelas, permanecendo limitados pelas
-- politicas administrativas da migration 007.

grant select on table public.admin_profiles to authenticated;

grant select, insert, update, delete on table
  public.departments,
  public.positions,
  public.schedules,
  public.employees,
  public.geofences,
  public.devices,
  public.device_tokens,
  public.punches,
  public.punch_adjustments,
  public.absences,
  public.occurrences,
  public.holidays,
  public.audit_events,
  public.settings
to authenticated;

select pg_notify('pgrst', 'reload schema');
