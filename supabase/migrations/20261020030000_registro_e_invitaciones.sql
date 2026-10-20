-- Registro de empresas, invitaciones y datos que la app necesita.

-- ─── Columnas para la app ────────────────────────────────────────────────────
alter table public.unidades    add column orden int not null default 0;
alter table public.pagos       add column registrado_nombre text;
alter table public.documentos  add column autor_nombre text;
alter table public.interesados add column por_nombre text;

-- ─── Invitaciones ────────────────────────────────────────────────────────────
-- El dueño invita por correo; al registrarse (o al entrar) la persona queda como miembro.
create table public.invitaciones (
  empresa_id uuid not null references public.empresas on delete cascade,
  email      text not null check (email = lower(email)),
  nombre     text not null,
  rol        text not null check (rol in ('dueno', 'secretaria')),
  creado     timestamptz not null default now(),
  aceptada   timestamptz,
  primary key (empresa_id, email)
);
alter table public.invitaciones enable row level security;
create policy invitaciones_lectura  on public.invitaciones for select to authenticated using (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma());
create policy invitaciones_insertar on public.invitaciones for insert to authenticated with check (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma(array['super_admin', 'soporte']));
create policy invitaciones_borrar   on public.invitaciones for delete to authenticated using (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma(array['super_admin', 'soporte']));

-- Administradores de plataforma pendientes de registrarse (sin acceso por API).
-- Los correos se cargan directo en la base, no en este repositorio.
create table privado.admins_invitados (
  email text primary key check (email = lower(email)),
  rol   text not null check (rol in ('super_admin', 'contabilidad', 'soporte'))
);

create or replace function privado.vincular_usuario(uid uuid, correo text)
returns void language plpgsql security definer set search_path = public, privado as $$
begin
  insert into admins_plataforma (user_id, rol)
    select uid, rol from admins_invitados where email = lower(correo)
    on conflict (user_id) do nothing;
  insert into miembros (empresa_id, user_id, nombre, rol)
    select empresa_id, uid, nombre, rol from invitaciones where email = lower(correo) and aceptada is null
    on conflict (empresa_id, user_id) do nothing;
  update invitaciones set aceptada = now() where email = lower(correo) and aceptada is null;
end $$;
revoke execute on function privado.vincular_usuario(uuid, text) from public, anon, authenticated;

create or replace function privado.al_crear_usuario() returns trigger
language plpgsql security definer set search_path = public, privado as $$
begin
  perform privado.vincular_usuario(new.id, new.email);
  return new;
end $$;
revoke execute on function privado.al_crear_usuario() from public, anon, authenticated;
create trigger al_crear_usuario after insert on auth.users
  for each row execute function privado.al_crear_usuario();

-- Para usuarios que ya existían cuando los invitaron
create or replace function public.aceptar_invitaciones() returns void
language plpgsql security definer set search_path = public, privado as $$
begin
  perform privado.vincular_usuario(auth.uid(), (select email from auth.users where id = auth.uid()));
end $$;
revoke execute on function public.aceptar_invitaciones() from public, anon;
grant execute on function public.aceptar_invitaciones() to authenticated;

-- ─── Alta de empresa (autoservicio, 14 días de prueba) ───────────────────────
create or replace function public.crear_empresa(p_nombre text, p_rut text, p_nombre_usuario text)
returns uuid language plpgsql security definer set search_path = public as $$
declare e uuid;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre de la empresa'; end if;
  if (select count(*) from miembros where user_id = auth.uid() and rol = 'dueno') >= 3 then
    raise exception 'Límite de empresas por usuario alcanzado';
  end if;
  insert into empresas (nombre, rut) values (trim(p_nombre), nullif(trim(p_rut), '')) returning id into e;
  insert into suscripciones (empresa_id, plan_id, estado, prueba_hasta) values (e, 'corredor', 'prueba', current_date + 14);
  insert into miembros (empresa_id, user_id, nombre, rol) values (e, auth.uid(), coalesce(nullif(trim(p_nombre_usuario), ''), 'Dueño'), 'dueno');
  insert into bitacora (empresa_id, user_id, usuario, accion) values (e, auth.uid(), p_nombre_usuario, 'Creó la empresa');
  return e;
end $$;
revoke execute on function public.crear_empresa(text, text, text) from public, anon;
grant execute on function public.crear_empresa(text, text, text) to authenticated;

-- ─── Límite de unidades según el plan ────────────────────────────────────────
create or replace function privado.limitar_unidades() returns trigger
language plpgsql security definer set search_path = public as $$
declare maximo int;
begin
  select p.max_unidades into maximo from suscripciones s join planes p on p.id = s.plan_id where s.empresa_id = new.empresa_id;
  if maximo is not null and (select count(*) from unidades where empresa_id = new.empresa_id) >= maximo then
    raise exception 'Tu plan permite hasta % unidades. Cambia de plan para agregar más.', maximo;
  end if;
  return new;
end $$;
revoke execute on function privado.limitar_unidades() from public, anon, authenticated;
create trigger unidades_limite before insert on public.unidades
  for each row execute function privado.limitar_unidades();

-- ─── Tiempo real ─────────────────────────────────────────────────────────────
alter publication supabase_realtime add table
  public.propiedades, public.unidades, public.contratos, public.pagos,
  public.documentos, public.interesados, public.empresas, public.miembros;
