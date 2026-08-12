-- ATENCAO: execute somente na base de homologacao antes do cadastro real.
-- Preserva schema, funcoes, permissoes e migrations; remove todos os dados.

begin;

truncate table
  public.punch_adjustments,
  public.punches,
  public.device_tokens,
  public.absences,
  public.occurrences,
  public.audit_events,
  public.devices,
  public.employees,
  public.geofences,
  public.holidays,
  public.settings,
  public.departments,
  public.positions,
  public.schedules
restart identity;

commit;
