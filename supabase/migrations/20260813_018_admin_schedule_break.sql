-- Jornadas: cadastro do intervalo de almoço (break) pelo Admin.

create or replace function public.admin_list_schedules()
returns jsonb language sql security definer set search_path = public as $$
  select coalesce(jsonb_agg(row_to_json(x)), '[]'::jsonb) from (
    select s.id, s.name, s.entry_time, s.exit_time, s.break_start, s.break_end,
           s.daily_minutes, s.tolerance_minutes, s.active, count(e.id) as employees
    from public.schedules s left join public.employees e on e.schedule_id = s.id
    where public.is_admin() group by s.id order by s.name
  ) x;
$$;

create or replace function public.admin_save_schedule(
  p_id uuid,
  p_name text,
  p_entry_time text,
  p_exit_time text,
  p_break_start text,
  p_break_end text,
  p_daily_minutes integer,
  p_tolerance_minutes integer
)
returns void language plpgsql security definer set search_path = public as $$
declare
  v_entry time := nullif(p_entry_time, '')::time;
  v_exit time := nullif(p_exit_time, '')::time;
  v_break_start time := nullif(p_break_start, '')::time;
  v_break_end time := nullif(p_break_end, '')::time;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_name, '')) = '' then raise exception 'Informe o nome da jornada.'; end if;
  if coalesce(p_daily_minutes, 0) < 0 then raise exception 'Carga diária inválida.'; end if;
  if coalesce(p_tolerance_minutes, 0) < 0 then raise exception 'Tolerância inválida.'; end if;
  if (v_break_start is null) <> (v_break_end is null) then
    raise exception 'Informe início e fim do intervalo juntos (ou deixe ambos em branco).';
  end if;
  if p_id is null then
    insert into public.schedules (name, entry_time, exit_time, break_start, break_end, daily_minutes, tolerance_minutes)
    values (trim(p_name), v_entry, v_exit, v_break_start, v_break_end, coalesce(p_daily_minutes, 0), coalesce(p_tolerance_minutes, 0));
  else
    update public.schedules set
      name = trim(p_name), entry_time = v_entry, exit_time = v_exit,
      break_start = v_break_start, break_end = v_break_end,
      daily_minutes = coalesce(p_daily_minutes, 0), tolerance_minutes = coalesce(p_tolerance_minutes, 0)
    where id = p_id;
  end if;
end; $$;

revoke all on function public.admin_save_schedule(uuid, text, text, text, text, text, integer, integer), public.admin_list_schedules() from public, anon;
grant execute on function public.admin_save_schedule(uuid, text, text, text, text, text, integer, integer), public.admin_list_schedules() to authenticated;

select pg_notify('pgrst', 'reload schema');
