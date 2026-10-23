-- Roles por empresa, corredores con comisión y cierre de los hallazgos de la auditoría de seguridad.
--
-- Roles: super_admin (antes "dueño"), admin (antes "secretaria", ahora con gestión completa salvo
-- los super administradores) y corredor (solo en planes con la función "propietarios", es decir,
-- corredoras). Un corredor opera como la antigua secretaria y cobra un % de la comisión de
-- administración de las propiedades que tiene a cargo.
--
-- Seguridad:
--  · Todas las políticas se reescriben: solo usuarios autenticados, toda escritura exige empresa
--    operativa (suspendida o cancelada = solo lectura) y la plataforma ya no lee datos de clientes
--    en forma permanente.
--  · Soporte HM entra a una empresa solo con un acceso temporal (2 horas) que se abre con motivo,
--    exige verificación en dos pasos (aal2) y queda en la bitácora del cliente.
--  · Llaves foráneas compuestas (empresa_id, id): nadie puede colgar filas de otra empresa.
--  · La bitácora toma el nombre del usuario desde el servidor y las acciones sensibles
--    (borrados, cambios bancarios, usuarios) se registran solas, aunque se use la API directa.
--  · Multas protegidas también al crear contratos, límite de usuarios también en miembros,
--    invitaciones solo con correo confirmado, formulario web con límite por IP.
--
-- En producción se aplicó en 5 partes (roles_corredores_seguridad_1..5) con ALTER POLICY en vez de
-- DROP/CREATE (el conector exige confirmación para borrar): mismas reglas, con los nombres de política
-- anteriores (p. ej. planes_admin en vez de planes_escribir). Quedan pendientes, por requerir esa
-- confirmación, borrar la vista torre_empresas (ya sin uso) y la fila sobrante de privado.admins_invitados.

-- ─── 1. Roles ────────────────────────────────────────────────────────────────
alter table public.miembros drop constraint miembros_rol_check;
alter table public.invitaciones drop constraint invitaciones_rol_check;
update public.miembros set rol = case rol when 'dueno' then 'super_admin' else 'admin' end where rol in ('dueno', 'secretaria');
update public.invitaciones set rol = case rol when 'dueno' then 'super_admin' else 'admin' end where rol in ('dueno', 'secretaria');
alter table public.miembros add constraint miembros_rol_check check (rol in ('super_admin', 'admin', 'corredor'));
alter table public.invitaciones add constraint invitaciones_rol_check check (rol in ('super_admin', 'admin', 'corredor'));

-- Comisión del corredor: % sobre la comisión de administración que cobra la corredora
alter table public.miembros add column comision_pct numeric(5,2) check (comision_pct between 0 and 100);
alter table public.invitaciones add column comision_pct numeric(5,2) check (comision_pct between 0 and 100);

-- ─── 2. Llaves foráneas por empresa ──────────────────────────────────────────
alter table public.propiedades add constraint propiedades_empresa_id_id_key unique (empresa_id, id);
alter table public.unidades    add constraint unidades_empresa_id_id_key unique (empresa_id, id);
alter table public.contratos   add constraint contratos_empresa_id_id_key unique (empresa_id, id);

alter table public.unidades drop constraint unidades_propiedad_id_fkey,
  add constraint unidades_propiedad_fk foreign key (empresa_id, propiedad_id) references public.propiedades (empresa_id, id) on delete cascade;
alter table public.contratos drop constraint contratos_unidad_id_fkey,
  add constraint contratos_unidad_fk foreign key (empresa_id, unidad_id) references public.unidades (empresa_id, id) on delete cascade;
alter table public.pagos drop constraint pagos_contrato_id_fkey,
  add constraint pagos_contrato_fk foreign key (empresa_id, contrato_id) references public.contratos (empresa_id, id) on delete cascade;
alter table public.abonos drop constraint abonos_contrato_id_fkey,
  add constraint abonos_contrato_fk foreign key (empresa_id, contrato_id) references public.contratos (empresa_id, id) on delete cascade;
alter table public.reajustes drop constraint reajustes_contrato_id_fkey,
  add constraint reajustes_contrato_fk foreign key (empresa_id, contrato_id) references public.contratos (empresa_id, id) on delete cascade;
alter table public.documentos drop constraint documentos_unidad_id_fkey,
  add constraint documentos_unidad_fk foreign key (empresa_id, unidad_id) references public.unidades (empresa_id, id) on delete cascade;
alter table public.interesados drop constraint interesados_unidad_id_fkey,
  add constraint interesados_unidad_fk foreign key (empresa_id, unidad_id) references public.unidades (empresa_id, id) on delete cascade;

-- Corredor a cargo de la propiedad (miembro de la misma empresa)
alter table public.propiedades add column corredor_id uuid;
alter table public.propiedades add constraint propiedades_corredor_fk
  foreign key (empresa_id, corredor_id) references public.miembros (empresa_id, user_id) on delete set null (corredor_id);
create index on public.propiedades (empresa_id, corredor_id);

-- Índices de llaves foráneas (antes en 20261020020000_optimizar_politicas.sql, que no llegó a aplicarse)
create index if not exists bitacora_user_id_idx on public.bitacora (user_id);
create index if not exists documentos_autor_idx on public.documentos (autor);
create index if not exists documentos_empresa_unidad_idx on public.documentos (empresa_id, unidad_id);
create index if not exists interesados_por_idx on public.interesados (por);
create index if not exists interesados_empresa_unidad_idx on public.interesados (empresa_id, unidad_id);
create index if not exists miembros_user_id_idx on public.miembros (user_id);
create index if not exists pagos_registrado_por_idx on public.pagos (registrado_por);
create index if not exists suscripciones_plan_id_idx on public.suscripciones (plan_id);
create index if not exists unidades_empresa_propiedad_idx on public.unidades (empresa_id, propiedad_id);
create index if not exists contratos_empresa_unidad_idx on public.contratos (empresa_id, unidad_id);
create index if not exists abonos_empresa_contrato_idx on public.abonos (empresa_id, contrato_id);

-- ─── 3. Acceso temporal de Soporte HM ────────────────────────────────────────
create table public.accesos_soporte (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  nombre     text not null,
  motivo     text not null check (length(trim(motivo)) >= 5),
  desde      timestamptz not null default now(),
  hasta      timestamptz not null,
  cerrado    timestamptz
);
create index on public.accesos_soporte (user_id, empresa_id, hasta);
create index on public.accesos_soporte (empresa_id, desde desc);

-- Configuración de la plataforma visible para los clientes (contacto de soporte, enlace de pago)
create table public.plataforma_config (
  clave text primary key,
  valor jsonb not null default '{}'
);
insert into public.plataforma_config (clave, valor) values ('contacto', '{}');

-- ─── 4. Funciones de permisos ────────────────────────────────────────────────
-- Verificación en dos pasos en la sesión actual
create or replace function privado.sesion_mfa() returns boolean
language sql stable set search_path = '' as $$
  select coalesce((select auth.jwt()) ->> 'aal', 'aal1') = 'aal2'
$$;

-- Admin de plataforma (exige verificación en dos pasos)
create or replace function privado.es_admin_plataforma(roles text[] default null) returns boolean
language sql stable security definer set search_path = public as $$
  select privado.sesion_mfa() and exists (select 1 from admins_plataforma a
                 where a.user_id = (select auth.uid()) and (roles is null or a.rol = any(roles)))
$$;

-- Soporte HM con acceso abierto a esa empresa
create or replace function privado.en_soporte(e uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select privado.sesion_mfa() and exists (
    select 1 from accesos_soporte s join admins_plataforma a on a.user_id = s.user_id and a.rol in ('super_admin', 'soporte')
    where s.empresa_id = e and s.user_id = (select auth.uid()) and s.hasta > now() and s.cerrado is null)
$$;

-- Miembro activo con alguno de los roles (Soporte HM con acceso abierto cuenta como super_admin)
create or replace function privado.es_miembro(e uuid, roles text[] default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros m
                 where m.empresa_id = e and m.user_id = (select auth.uid()) and m.activo
                   and (roles is null or m.rol = any(roles)))
      or privado.en_soporte(e)
$$;

-- Administra la empresa: super_admin o admin
create or replace function privado.es_admin(e uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select privado.es_miembro(e, array['super_admin', 'admin'])
$$;

-- Nombre con que queda en la bitácora quien actúa
create or replace function privado.nombre_actor(e uuid) returns text
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select m.nombre from miembros m where m.empresa_id = e and m.user_id = (select auth.uid()) and m.activo),
    (select 'Soporte HM · ' || s.nombre from accesos_soporte s where s.empresa_id = e and s.user_id = (select auth.uid())
       and s.hasta > now() and s.cerrado is null order by s.desde desc limit 1),
    (select coalesce(u.raw_user_meta_data ->> 'nombre', u.email) from auth.users u where u.id = (select auth.uid())))
$$;

revoke execute on function privado.sesion_mfa(), privado.en_soporte(uuid), privado.es_admin(uuid), privado.nombre_actor(uuid) from public, anon;
grant execute on function privado.sesion_mfa(), privado.en_soporte(uuid), privado.es_admin(uuid), privado.nombre_actor(uuid) to authenticated;

-- ─── 5. Políticas: se reescriben todas ───────────────────────────────────────
do $$
declare r record;
begin
  for r in select schemaname, tablename, policyname from pg_policies where schemaname = 'public' loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
  end loop;
end $$;

alter table public.accesos_soporte enable row level security;
alter table public.plataforma_config enable row level security;

-- Plataforma
create policy admins_lectura on public.admins_plataforma for select to authenticated
  using (user_id = (select auth.uid()) or privado.es_admin_plataforma());
create policy planes_lectura on public.planes for select to authenticated using (true);
create policy planes_escribir on public.planes for all to authenticated
  using (privado.es_admin_plataforma(array['super_admin'])) with check (privado.es_admin_plataforma(array['super_admin']));
create policy config_lectura on public.plataforma_config for select to authenticated using (true);
create policy config_escribir on public.plataforma_config for all to authenticated
  using (privado.es_admin_plataforma(array['super_admin'])) with check (privado.es_admin_plataforma(array['super_admin']));
-- El cliente ve quién de soporte entró a su empresa y por qué
create policy accesos_lectura on public.accesos_soporte for select to authenticated
  using (privado.es_admin(empresa_id) or privado.es_admin_plataforma());

-- Empresa y suscripción
create policy empresas_lectura on public.empresas for select to authenticated
  using (privado.es_miembro(id) or privado.es_admin_plataforma());
create policy empresas_editar on public.empresas for update to authenticated
  using (privado.es_admin(id) or privado.es_admin_plataforma(array['super_admin']))
  with check ((privado.es_admin(id) and privado.empresa_operativa(id)) or privado.es_admin_plataforma(array['super_admin']));
create policy empresas_borrar on public.empresas for delete to authenticated using (privado.es_admin_plataforma(array['super_admin']));
create policy suscripciones_lectura on public.suscripciones for select to authenticated
  using (privado.es_miembro(empresa_id) or privado.es_admin_plataforma());
create policy suscripciones_escribir on public.suscripciones for all to authenticated
  using (privado.es_admin_plataforma(array['super_admin', 'contabilidad'])) with check (privado.es_admin_plataforma(array['super_admin', 'contabilidad']));
create policy cobros_lectura on public.cobros_suscripcion for select to authenticated
  using (privado.es_admin(empresa_id) or privado.es_admin_plataforma());
create policy cobros_escribir on public.cobros_suscripcion for all to authenticated
  using (privado.es_admin_plataforma(array['super_admin', 'contabilidad'])) with check (privado.es_admin_plataforma(array['super_admin', 'contabilidad']));

-- Usuarios: los admins gestionan admins y corredores; solo un super_admin crea o toca super_admins.
-- El rol corredor existe solo en planes de corredora.
create or replace function privado.puede_asignar_rol(e uuid, rol text) returns boolean
language sql stable security definer set search_path = public as $$
  select privado.es_admin(e) and privado.empresa_operativa(e)
     and (rol <> 'super_admin' or privado.es_miembro(e, array['super_admin']))
     and (rol <> 'corredor' or privado.plan_permite(e, 'propietarios'))
$$;
revoke execute on function privado.puede_asignar_rol(uuid, text) from public, anon;
grant execute on function privado.puede_asignar_rol(uuid, text) to authenticated;

create policy miembros_lectura on public.miembros for select to authenticated
  using (privado.es_miembro(empresa_id) or privado.es_admin_plataforma());
create policy miembros_insertar on public.miembros for insert to authenticated
  with check (privado.puede_asignar_rol(empresa_id, rol));
create policy miembros_editar on public.miembros for update to authenticated
  using (privado.es_admin(empresa_id) and (rol <> 'super_admin' or privado.es_miembro(empresa_id, array['super_admin'])))
  with check (privado.puede_asignar_rol(empresa_id, rol));
create policy miembros_borrar on public.miembros for delete to authenticated
  using (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id)
         and (rol <> 'super_admin' or privado.es_miembro(empresa_id, array['super_admin'])));

create policy invitaciones_lectura on public.invitaciones for select to authenticated using (privado.es_admin(empresa_id));
create policy invitaciones_insertar on public.invitaciones for insert to authenticated with check (privado.puede_asignar_rol(empresa_id, rol));
create policy invitaciones_borrar on public.invitaciones for delete to authenticated
  using (privado.es_admin(empresa_id) and (rol <> 'super_admin' or privado.es_miembro(empresa_id, array['super_admin'])));

-- Cartera: todo miembro lee y edita; borrar es de administradores. Escritura solo con empresa operativa.
do $$
declare t text;
begin
  foreach t in array array['propiedades', 'unidades', 'contratos', 'documentos', 'interesados'] loop
    execute format('create policy %1$s_lectura on public.%1$I for select to authenticated using (privado.es_miembro(empresa_id))', t);
    execute format('create policy %1$s_insertar on public.%1$I for insert to authenticated with check (privado.es_miembro(empresa_id) and privado.empresa_operativa(empresa_id))', t);
    execute format('create policy %1$s_editar on public.%1$I for update to authenticated using (privado.es_miembro(empresa_id)) with check (privado.es_miembro(empresa_id) and privado.empresa_operativa(empresa_id))', t);
    execute format('create policy %1$s_borrar on public.%1$I for delete to authenticated using (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id))', t);
  end loop;
  -- Pagos, abonos y reajustes: todos registran; corregir o borrar es de administradores
  foreach t in array array['pagos', 'abonos', 'reajustes'] loop
    execute format('create policy %1$s_lectura on public.%1$I for select to authenticated using (privado.es_miembro(empresa_id))', t);
    execute format('create policy %1$s_insertar on public.%1$I for insert to authenticated with check (privado.es_miembro(empresa_id) and privado.empresa_operativa(empresa_id))', t);
    execute format('create policy %1$s_editar on public.%1$I for update to authenticated using (privado.es_admin(empresa_id)) with check (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id))', t);
    execute format('create policy %1$s_borrar on public.%1$I for delete to authenticated using (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id))', t);
  end loop;
end $$;

-- Propietarios: todos ven el nombre y contacto; los administradores los gestionan.
-- Datos bancarios y liquidaciones: solo administradores.
create policy propietarios_lectura on public.propietarios for select to authenticated using (privado.es_miembro(empresa_id));
create policy propietarios_insertar on public.propietarios for insert to authenticated
  with check (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id) and privado.plan_permite(empresa_id, 'propietarios'));
create policy propietarios_editar on public.propietarios for update to authenticated
  using (privado.es_admin(empresa_id)) with check (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id));
create policy propietarios_borrar on public.propietarios for delete to authenticated
  using (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id));

create policy propietarios_banco_lectura on public.propietarios_banco for select to authenticated using (privado.es_admin(empresa_id));
create policy propietarios_banco_insertar on public.propietarios_banco for insert to authenticated
  with check (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id));
create policy propietarios_banco_editar on public.propietarios_banco for update to authenticated
  using (privado.es_admin(empresa_id)) with check (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id));
create policy propietarios_banco_borrar on public.propietarios_banco for delete to authenticated
  using (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id));

create policy liquidaciones_lectura on public.liquidaciones for select to authenticated using (privado.es_admin(empresa_id));
create policy liquidaciones_insertar on public.liquidaciones for insert to authenticated
  with check (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id) and privado.plan_permite(empresa_id, 'propietarios'));
create policy liquidaciones_editar on public.liquidaciones for update to authenticated
  using (privado.es_admin(empresa_id)) with check (privado.es_admin(empresa_id) and privado.empresa_operativa(empresa_id));

-- Bitácora: no se edita ni se borra; la leen los administradores (y la plataforma, la suya)
create policy bitacora_lectura on public.bitacora for select to authenticated
  using (privado.es_admin(empresa_id) or (empresa_id is null and privado.es_admin_plataforma()));
create policy bitacora_insertar on public.bitacora for insert to authenticated
  with check (user_id = (select auth.uid()) and (privado.es_miembro(empresa_id) or (empresa_id is null and privado.es_admin_plataforma())));

-- Fotos: escribir y borrar solo con empresa operativa
drop policy if exists fotos_subir on storage.objects;
drop policy if exists fotos_borrar on storage.objects;
create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos' and privado.es_miembro(privado.empresa_de_ruta(name)) and privado.empresa_operativa(privado.empresa_de_ruta(name)));
create policy fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and privado.es_miembro(privado.empresa_de_ruta(name)) and privado.empresa_operativa(privado.empresa_de_ruta(name)));

-- La vista con security_invoker ya no sirve a la plataforma (no lee la cartera): la reemplaza una función
drop view if exists public.torre_empresas;

-- ─── 6. Reglas de negocio en el servidor ─────────────────────────────────────
-- Multas: solo administradores las activan, cambian o condonan (también al crear un contrato)
create or replace function privado.proteger_multa() returns trigger
language plpgsql security definer set search_path = public, privado as $$
begin
  if privado.es_admin(new.empresa_id) or auth.uid() is null then return new; end if;
  if tg_op = 'INSERT' then
    if coalesce((new.multa ->> 'cobrar')::boolean, false) or cardinality(new.multas_condonadas) > 0 then
      raise exception 'Solo un administrador puede activar o condonar multas';
    end if;
  elsif new.multa is distinct from old.multa or new.multas_condonadas is distinct from old.multas_condonadas then
    raise exception 'Solo un administrador puede cambiar o condonar multas';
  end if;
  return new;
end $$;
drop trigger if exists contratos_proteger_multa on public.contratos;
create trigger contratos_proteger_multa before insert or update on public.contratos
  for each row execute function privado.proteger_multa();

-- Corredor a cargo: lo asignan los administradores; solo puede ser un corredor
create or replace function privado.proteger_corredor() returns trigger
language plpgsql security definer set search_path = public, privado as $$
begin
  if new.corredor_id is not distinct from (case when tg_op = 'UPDATE' then old.corredor_id end) then return new; end if;
  if auth.uid() is not null and not privado.es_admin(new.empresa_id) then
    raise exception 'Solo un administrador asigna el corredor a cargo';
  end if;
  if new.corredor_id is not null and not exists (select 1 from miembros where empresa_id = new.empresa_id and user_id = new.corredor_id and rol = 'corredor') then
    raise exception 'El usuario asignado no es corredor de la empresa';
  end if;
  return new;
end $$;
create trigger propiedades_proteger_corredor before insert or update on public.propiedades
  for each row execute function privado.proteger_corredor();

-- Siempre queda al menos un super administrador activo
create or replace function privado.proteger_super_admin() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if old.rol = 'super_admin' and old.activo
     and (tg_op = 'DELETE' or new.rol <> 'super_admin' or not new.activo)
     and exists (select 1 from empresas where id = old.empresa_id)
     and not exists (select 1 from miembros where empresa_id = old.empresa_id and rol = 'super_admin' and activo and user_id <> old.user_id) then
    raise exception 'La empresa debe tener al menos un super administrador activo';
  end if;
  return coalesce(new, old);
end $$;
create trigger miembros_proteger_super_admin before update or delete on public.miembros
  for each row execute function privado.proteger_super_admin();

-- Límite de usuarios del plan: miembros activos + invitaciones pendientes
create or replace function privado.limitar_usuarios() returns trigger
language plpgsql security definer set search_path = public as $$
declare maximo int;
begin
  if tg_table_name = 'miembros' and not (to_jsonb(new) ->> 'activo')::boolean then return new; end if;
  -- al aceptar una invitación el cupo ya se contó al invitar
  if tg_table_name = 'miembros' and not privado.es_admin(new.empresa_id) then return new; end if;
  if tg_op = 'UPDATE' and (to_jsonb(old) ->> 'activo')::boolean then return new; end if;
  select p.max_usuarios into maximo from suscripciones s join planes p on p.id = s.plan_id where s.empresa_id = new.empresa_id;
  if maximo is not null and
     (select count(*) from miembros where empresa_id = new.empresa_id and activo)
     + (select count(*) from invitaciones where empresa_id = new.empresa_id and aceptada is null) >= maximo then
    raise exception 'Tu plan permite hasta % usuarios. Cambia de plan para invitar a más.', maximo;
  end if;
  return new;
end $$;
create trigger miembros_limite before insert or update of activo on public.miembros
  for each row execute function privado.limitar_usuarios();

-- Invitaciones: se aceptan al confirmar el correo (primero se marca la invitación, luego se crea el miembro)
create or replace function privado.vincular_usuario(uid uuid, correo text) returns void
language plpgsql security definer set search_path = public, privado as $$
begin
  perform privado.vincular_usuario_interno(uid, correo);
exception when others then
  -- nunca bloquear el registro o la confirmación del correo por una invitación con problemas
  raise warning 'No se pudo aceptar la invitación de %: %', correo, sqlerrm;
end $$;

create or replace function privado.vincular_usuario_interno(uid uuid, correo text) returns void
language plpgsql security definer set search_path = public, privado as $$
begin
  if not exists (select 1 from auth.users where id = uid and email_confirmed_at is not null) then return; end if;
  insert into admins_plataforma (user_id, rol)
    select uid, rol from admins_invitados where email = lower(correo)
    on conflict (user_id) do nothing;
  delete from admins_invitados where email = lower(correo);
  with aceptadas as (
    update invitaciones set aceptada = now() where email = lower(correo) and aceptada is null
    returning empresa_id, nombre, rol, comision_pct)
  insert into miembros (empresa_id, user_id, nombre, rol, comision_pct)
    select empresa_id, uid, nombre, rol, comision_pct from aceptadas
    on conflict (empresa_id, user_id) do update set activo = true, rol = excluded.rol, comision_pct = excluded.comision_pct;
end $$;
revoke execute on function privado.vincular_usuario(uuid, text), privado.vincular_usuario_interno(uuid, text) from public, anon, authenticated;

drop trigger if exists al_crear_usuario on auth.users;
create trigger al_crear_usuario after insert or update of email_confirmed_at on auth.users
  for each row execute function privado.al_crear_usuario();
-- Admins de plataforma ya registrados: su invitación sobra
delete from privado.admins_invitados i using auth.users u where u.email = i.email;

-- Crear empresa: quien la crea es su super administrador
create or replace function public.crear_empresa(p_nombre text, p_rut text, p_nombre_usuario text) returns uuid
language plpgsql security definer set search_path = public as $$
declare e uuid;
begin
  if auth.uid() is null then raise exception 'Debes iniciar sesión'; end if;
  if coalesce(trim(p_nombre), '') = '' then raise exception 'Falta el nombre de la empresa'; end if;
  if (select count(*) from miembros where user_id = auth.uid() and rol = 'super_admin') >= 3 then
    raise exception 'Límite de empresas por usuario alcanzado';
  end if;
  insert into empresas (nombre, rut) values (trim(p_nombre), nullif(trim(p_rut), '')) returning id into e;
  insert into suscripciones (empresa_id, plan_id, estado, prueba_hasta) values (e, 'corredor', 'prueba', current_date + 14);
  insert into miembros (empresa_id, user_id, nombre, rol) values (e, auth.uid(), coalesce(nullif(trim(p_nombre_usuario), ''), 'Administrador'), 'super_admin');
  insert into bitacora (empresa_id, user_id, usuario, accion) values (e, auth.uid(), p_nombre_usuario, 'Creó la empresa');
  return e;
end $$;

-- ─── 7. Bitácora en el servidor ──────────────────────────────────────────────
-- El nombre lo pone el servidor (no se puede firmar como otro)
create or replace function privado.bitacora_actor() returns trigger
language plpgsql security definer set search_path = public, privado as $$
begin
  if auth.uid() is not null then
    new.user_id := auth.uid();
    new.usuario := case when new.empresa_id is null
      then (select coalesce(u.raw_user_meta_data ->> 'nombre', u.email) from auth.users u where u.id = auth.uid())
      else privado.nombre_actor(new.empresa_id) end;
  end if;
  new.creado := now();
  return new;
end $$;
create trigger bitacora_actor before insert on public.bitacora
  for each row execute function privado.bitacora_actor();

-- Registro automático de acciones sensibles (aunque se use la API directa). Los borrados en cascada
-- (al eliminar una propiedad o la empresa) no se repiten fila por fila.
create or replace function privado.auditar() returns trigger
language plpgsql security definer set search_path = public, privado as $$
declare o jsonb := case when tg_op <> 'INSERT' then to_jsonb(old) end;
        n jsonb := case when tg_op <> 'DELETE' then to_jsonb(new) end;
        r jsonb := coalesce(n, o); e uuid := (r ->> 'empresa_id')::uuid; txt text; quien text;
begin
  if pg_trigger_depth() > 1 or auth.uid() is null or not exists (select 1 from empresas where id = e) then return null; end if;
  if tg_table_name = 'liquidaciones' and n ->> 'estado' = o ->> 'estado' then return null; end if;
  if tg_table_name = 'miembros' and tg_op = 'UPDATE' and n ->> 'rol' = o ->> 'rol' and n ->> 'activo' = o ->> 'activo'
     and (n ->> 'comision_pct') is not distinct from (o ->> 'comision_pct') then return null; end if;
  quien := (select arrendatario ->> 'nombre' from contratos where id = (r ->> 'contrato_id')::uuid);
  txt := case tg_table_name
    when 'pagos' then format('%s pago de %s (%s) de %s', case tg_op when 'DELETE' then 'Eliminó el' else 'Modificó el' end,
                             r ->> 'periodo', '$' || replace(to_char((r ->> 'monto_clp')::int, 'FM999,999,999'), ',', '.'), coalesce(quien, 'contrato eliminado'))
    when 'abonos' then format('%s abono de %s (%s) de %s', case tg_op when 'DELETE' then 'Eliminó el' else 'Modificó el' end,
                             r ->> 'periodo', '$' || replace(to_char((r ->> 'monto_clp')::int, 'FM999,999,999'), ',', '.'), coalesce(quien, 'contrato eliminado'))
    when 'contratos' then format('Eliminó el contrato de %s', o -> 'arrendatario' ->> 'nombre')
    when 'propiedades' then format('Eliminó la propiedad "%s"', o ->> 'nombre')
    when 'unidades' then format('Eliminó la unidad "%s"', o ->> 'nombre')
    when 'propietarios' then format('Eliminó al propietario %s', o ->> 'nombre')
    when 'propietarios_banco' then format('%s datos bancarios del propietario %s', case tg_op when 'DELETE' then 'Eliminó' when 'INSERT' then 'Agregó' else 'Cambió' end,
                             (select nombre from propietarios where id = (r ->> 'id')::uuid))
    when 'reajustes' then format('Deshizo el reajuste de %s', o ->> 'desde')
    when 'documentos' then format('Eliminó el documento "%s"', o ->> 'titulo')
    when 'liquidaciones' then format('Liquidación %s: %s → %s', r ->> 'periodo', o ->> 'estado', n ->> 'estado')
    when 'miembros' then case tg_op
      when 'INSERT' then format('Agregó a %s como %s', n ->> 'nombre', n ->> 'rol')
      when 'DELETE' then format('Quitó a %s (%s)', o ->> 'nombre', o ->> 'rol')
      else format('Usuario %s: %s%s%s', n ->> 'nombre',
             case when n ->> 'rol' <> o ->> 'rol' then format('rol %s → %s ', o ->> 'rol', n ->> 'rol') else '' end,
             case when n ->> 'activo' <> o ->> 'activo' then case when (n ->> 'activo')::boolean then 'reactivado ' else 'desactivado ' end else '' end,
             case when (n ->> 'comision_pct') is distinct from (o ->> 'comision_pct') then format('comisión %s%% → %s%%', coalesce(o ->> 'comision_pct', '0'), coalesce(n ->> 'comision_pct', '0')) else '' end) end
  end;
  insert into bitacora (empresa_id, user_id, usuario, accion) values (e, auth.uid(), privado.nombre_actor(e), '🔒 ' || txt);
  return null;
end $$;
create trigger auditar after update or delete on public.pagos for each row execute function privado.auditar();
create trigger auditar after update or delete on public.abonos for each row execute function privado.auditar();
create trigger auditar after delete on public.contratos for each row execute function privado.auditar();
create trigger auditar after delete on public.propiedades for each row execute function privado.auditar();
create trigger auditar after delete on public.unidades for each row execute function privado.auditar();
create trigger auditar after delete on public.propietarios for each row execute function privado.auditar();
create trigger auditar after insert or update or delete on public.propietarios_banco for each row execute function privado.auditar();
create trigger auditar after delete on public.reajustes for each row execute function privado.auditar();
create trigger auditar after delete on public.documentos for each row execute function privado.auditar();
create trigger auditar after update on public.liquidaciones for each row execute function privado.auditar();
create trigger auditar after insert or update or delete on public.miembros for each row execute function privado.auditar();
revoke execute on function privado.auditar(), privado.bitacora_actor(), privado.proteger_corredor(), privado.proteger_super_admin() from public, anon, authenticated;

-- ─── 8. Soporte y panel de plataforma ────────────────────────────────────────
-- Abre (o renueva) un acceso de 2 horas a una empresa, con motivo; queda en la bitácora del cliente
create or replace function public.abrir_acceso_soporte(p_empresa uuid, p_motivo text) returns timestamptz
language plpgsql security definer set search_path = public, privado as $$
declare h timestamptz := now() + interval '2 hours'; n text;
begin
  if not privado.es_admin_plataforma(array['super_admin', 'soporte']) then
    raise exception 'Requiere ser soporte de la plataforma con verificación en dos pasos';
  end if;
  if length(trim(coalesce(p_motivo, ''))) < 5 then raise exception 'Indica el motivo del acceso'; end if;
  if not exists (select 1 from empresas where id = p_empresa) then raise exception 'Empresa no encontrada'; end if;
  select coalesce(raw_user_meta_data ->> 'nombre', email) into n from auth.users where id = auth.uid();
  update accesos_soporte set cerrado = now() where user_id = auth.uid() and empresa_id = p_empresa and cerrado is null;
  insert into accesos_soporte (empresa_id, user_id, nombre, motivo, hasta) values (p_empresa, auth.uid(), n, trim(p_motivo), h);
  insert into bitacora (empresa_id, user_id, usuario, accion)
    values (p_empresa, auth.uid(), 'Soporte HM · ' || n, '🛟 Soporte HM entró a la cuenta (2 horas). Motivo: ' || trim(p_motivo));
  return h;
end $$;

create or replace function public.cerrar_acceso_soporte(p_empresa uuid) returns void
language sql security definer set search_path = public as $$
  update accesos_soporte set cerrado = now() where user_id = auth.uid() and empresa_id = p_empresa and cerrado is null;
$$;

-- Resumen por empresa para el panel de plataforma (solo totales, sin datos de la cartera)
create or replace function public.plataforma_empresas() returns table (
  id uuid, nombre text, rut text, email text, telefono text, creado timestamptz, plan_id text, plan text, estado text,
  prueba_hasta date, vigente_hasta date, unidades bigint, ocupadas bigint, mrr_clp integer, ciclo text,
  cobros_pendientes bigint, ultima_actividad timestamptz)
language sql stable security definer set search_path = public as $$
  select e.id, e.nombre, e.rut, e.email, e.telefono, e.creado, s.plan_id, p.nombre, s.estado, s.prueba_hasta, s.vigente_hasta,
         (select count(*) from unidades u where u.empresa_id = e.id),
         (select count(*) from contratos c where c.empresa_id = e.id and c.vigente),
         coalesce(s.precio_clp_pactado, p.precio_clp), s.ciclo,
         (select count(*) from cobros_suscripcion cs where cs.empresa_id = e.id and cs.estado = 'pendiente'),
         (select max(m.creado) from bitacora m where m.empresa_id = e.id)
  from empresas e left join suscripciones s on s.empresa_id = e.id left join planes p on p.id = s.plan_id
  where privado.es_admin_plataforma()
  order by e.creado desc
$$;

revoke execute on function public.abrir_acceso_soporte(uuid, text), public.cerrar_acceso_soporte(uuid), public.plataforma_empresas() from public, anon;
grant execute on function public.abrir_acceso_soporte(uuid, text), public.cerrar_acceso_soporte(uuid), public.plataforma_empresas() to authenticated;

-- ─── 9. Formulario web: límite por IP además del límite por empresa ──────────
alter table public.interesados add column origen text;   -- huella diaria de la IP (no se guarda la IP)

create or replace function public.web_contacto(p_slug text, p_unidad uuid, p_nombre text, p_telefono text, p_email text, p_mensaje text)
returns void language plpgsql security definer set search_path = public as $$
declare e uuid; nombre text := left(trim(coalesce(p_nombre, '')), 100);
        tel text := left(trim(coalesce(p_telefono, '')), 30); correo text := left(lower(trim(coalesce(p_email, ''))), 120);
        h json := nullif(current_setting('request.headers', true), '')::json;
        huella text := md5(coalesce(split_part(coalesce(h ->> 'x-forwarded-for', h ->> 'x-real-ip', ''), ',', 1), '') || current_date::text);
begin
  select em.id into e from empresas em join unidades u on u.empresa_id = em.id join suscripciones s on s.empresa_id = em.id
   where em.slug = lower(trim(p_slug)) and coalesce((em.web->>'activa')::boolean, false) and s.estado in ('prueba', 'activa', 'morosa')
     and u.id = p_unidad and u.publicar
     and not exists (select 1 from contratos c where c.unidad_id = u.id and c.vigente);
  if e is null then raise exception 'Propiedad no disponible'; end if;
  if length(nombre) < 2 then raise exception 'Ingresa tu nombre'; end if;
  if tel = '' and correo = '' then raise exception 'Ingresa un teléfono o correo'; end if;
  if correo <> '' and correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo inválido'; end if;
  -- límites contra abuso: 5 por hora desde una misma conexión, 30 por hora y 150 por día por inmobiliaria
  if (select count(*) from interesados where origen = huella and creado > now() - interval '1 hour') >= 5
     or (select count(*) from interesados where empresa_id = e and canal = 'Sitio web' and creado > now() - interval '1 hour') >= 30
     or (select count(*) from interesados where empresa_id = e and canal = 'Sitio web' and creado > now() - interval '1 day') >= 150 then
    raise exception 'Demasiadas solicitudes. Intenta más tarde.';
  end if;
  insert into interesados (empresa_id, unidad_id, nombre, telefono, email, nota, canal, por_nombre, origen)
  values (e, p_unidad, nombre, nullif(tel, ''), nullif(correo, ''),
          coalesce(nullif(left(trim(coalesce(p_mensaje, '')), 1000), ''), 'Pidió información desde la página web'), 'Sitio web', 'Sitio web', huella);
  insert into bitacora (empresa_id, usuario, accion)
  select e, 'Sitio web', 'Nuevo interesado desde la web: ' || nombre || ' (' || (select case when p.tipo = 'centro' then p.nombre || ' · ' || u.nombre else p.nombre end
    from unidades u join propiedades p on p.id = u.propiedad_id where u.id = p_unidad) || ')';
end $$;
create index on public.interesados (origen, creado);

-- ─── 10. Permisos de tabla ───────────────────────────────────────────────────
revoke truncate on all tables in schema public from anon, authenticated;
revoke all on public.accesos_soporte from anon;
revoke insert, update, delete on public.accesos_soporte from authenticated;

