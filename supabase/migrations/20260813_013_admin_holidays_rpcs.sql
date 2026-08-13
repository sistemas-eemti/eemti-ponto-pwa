-- Gestao de feriados no Admin.

create or replace function public.admin_list_holidays()
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.holiday_date), '[]'::jsonb) into v_rows from (
    select h.holiday_date, h.description, h.type
    from public.holidays h
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

create or replace function public.admin_save_holiday(p_date date, p_description text, p_type text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_date is null or trim(coalesce(p_description, '')) = '' then
    raise exception 'Informe a data e a descrição do feriado.';
  end if;
  insert into public.holidays (holiday_date, description, type)
  values (p_date, trim(p_description), coalesce(nullif(trim(p_type), ''), 'national'))
  on conflict (holiday_date) do update
    set description = excluded.description, type = excluded.type;
end; $$;

create or replace function public.admin_delete_holiday(p_date date)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  delete from public.holidays where holiday_date = p_date;
end; $$;

revoke all on function public.admin_list_holidays(), public.admin_save_holiday(date, text, text), public.admin_delete_holiday(date) from public, anon;
grant execute on function public.admin_list_holidays(), public.admin_save_holiday(date, text, text), public.admin_delete_holiday(date) to authenticated;

select pg_notify('pgrst', 'reload schema');
