-- Corrección de seguridad (advisors de Supabase): funciones de permisos fuera de la API pública.

-- ─── Seguridad: funciones de permisos fuera de la API pública ────────────────
-- Las políticas guardan la referencia a la función, así que siguen funcionando
-- tras moverlas. Solo los usuarios autenticados las ejecutan (al evaluar RLS).
create schema if not exists privado;
revoke all on schema privado from public;
grant usage on schema privado to authenticated;

alter function public.es_admin_plataforma(text[])  set schema privado;
alter function public.es_miembro(uuid, text[])     set schema privado;
alter function public.empresa_operativa(uuid)      set schema privado;
alter function public.proteger_multa()             set schema privado;

alter function privado.es_admin_plataforma(text[]) set search_path = public;
alter function privado.es_miembro(uuid, text[])    set search_path = public;
alter function privado.empresa_operativa(uuid)     set search_path = public;
alter function privado.proteger_multa()            set search_path = public, privado;

revoke execute on all functions in schema privado from public, anon;
grant execute on function privado.es_admin_plataforma(text[]), privado.es_miembro(uuid, text[]),
  privado.empresa_operativa(uuid) to authenticated;
revoke execute on function privado.proteger_multa() from authenticated;
