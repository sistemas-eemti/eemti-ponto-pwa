-- Gestao de batidas no Admin: listagem e exclusao (apos apos marcacao).

create or replace function public.admin_list_punches(p_start date, p_end date)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_start is null or p_end is null then raise exception 'Informe o período.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.captured_at desc), '[]'::jsonb) into v_rows from (
    select p.id, e.enrollment, e.name,
           to_char(p.captured_at at time zone 'America/Fortaleza', 'DD/MM/YYYY HH24:MI') as captured_at,
           p.origin, p.captured_offline, p.inside_geofence,
           round(p.distance_meters) as distance_meters,
           p.excluded_at is not null as excluded
    from public.punches p
    join public.employees e on e.id = p.employee_id
    where p.captured_at >= p_start::timestamptz
      and p.captured_at < (p_end + interval '1 day')::timestamptz
    order by p.captured_at desc
    limit 2000
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

create or replace function public.admin_delete_punch(p_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = public, auth as $$
declare
  v_punch public.punches%rowtype;
  v_actor text := auth.jwt() ->> 'email';
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_id is null or trim(coalesce(p_reason, '')) = '' then
    raise exception 'Informe o motivo da exclusão.';
  end if;
  select * into v_punch from public.punches where id = p_id;
  if not found then raise exception 'Batida não encontrada.'; end if;
  if v_punch.excluded_at is not null then raise exception 'Esta batida já foi excluída.'; end if;

  update public.punches set excluded_at = now() where id = p_id;

  insert into public.punch_adjustments (punch_id, kind, reason, before_value, requested_by, approved_by)
  values (p_id, 'exclude', trim(p_reason), to_jsonb(v_punch), coalesce(v_actor, 'admin'), coalesce(v_actor, 'admin'));
end; $$;

revoke all on function public.admin_list_punches(date, date), public.admin_delete_punch(uuid, text) from public, anon;
grant execute on function public.admin_list_punches(date, date), public.admin_delete_punch(uuid, text) to authenticated;

select pg_notify('pgrst', 'reload schema');
