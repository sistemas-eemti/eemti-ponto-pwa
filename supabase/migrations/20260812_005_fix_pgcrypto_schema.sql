-- No Supabase, pgcrypto fica no schema extensions. A função original já foi
-- criada, então atualizamos seu contexto de execução na base existente.

alter function public.sync_punch(
  text, text, text, text, timestamptz, boolean, numeric, numeric, numeric, text, text
) set search_path = public, extensions;

select pg_notify('pgrst', 'reload schema');
