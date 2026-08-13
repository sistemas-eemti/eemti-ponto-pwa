-- Gestao de perfis de acesso no Admin (admin/operator).

create or replace function public.admin_list_profiles()
returns jsonb language plpgsql security definer set search_path = public, auth as $$
declare v_rows jsonb;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  select coalesce(jsonb_agg(row_to_json(x) order by x.email), '[]'::jsonb) into v_rows from (
    select p.user_id, u.email, p.role, p.display_name, p.active, p.created_at
    from public.admin_profiles p
    join auth.users u on u.id = p.user_id
  ) x;
  return jsonb_build_object('rows', v_rows);
end; $$;

create or replace function public.admin_save_profile(p_user_email text, p_role text, p_display_name text, p_active boolean)
returns void language plpgsql security definer set search_path = public, auth as $$
declare
  v_user_id uuid;
  v_target_is_self boolean;
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if trim(coalesce(p_user_email, '')) = '' then raise exception 'Informe o e-mail da conta.'; end if;
  if p_role not in ('admin', 'operator') then raise exception 'Perfil inválido.'; end if;

  select id into v_user_id from auth.users where lower(email) = lower(trim(p_user_email));
  if v_user_id is null then
    raise exception 'Conta não encontrada no Supabase Auth. Crie o usuário em Authentication > Users antes de vincular.';
  end if;

  v_target_is_self := (v_user_id = auth.uid());
  if v_target_is_self and (p_role <> 'admin' or p_active = false) then
    raise exception 'Você não pode remover o próprio acesso administrativo.';
  end if;

  insert into public.admin_profiles (user_id, role, display_name, active)
  values (v_user_id, p_role, coalesce(nullif(trim(p_display_name), ''), null), coalesce(p_active, true))
  on conflict (user_id) do update
    set role = excluded.role, display_name = excluded.display_name, active = excluded.active, updated_at = now();
end; $$;

create or replace function public.admin_delete_profile(p_user_id uuid)
returns void language plpgsql security definer set search_path = public, auth as $$
begin
  if not public.is_admin() then raise exception 'Acesso administrativo negado.'; end if;
  if p_user_id = auth.uid() then raise exception 'Você não pode remover o próprio acesso.'; end if;
  delete from public.admin_profiles where user_id = p_user_id;
end; $$;

revoke all on function public.admin_list_profiles(), public.admin_save_profile(text, text, text, boolean), public.admin_delete_profile(uuid) from public, anon;
grant execute on function public.admin_list_profiles(), public.admin_save_profile(text, text, text, boolean), public.admin_delete_profile(uuid) to authenticated;

select pg_notify('pgrst', 'reload schema');
