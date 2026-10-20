-- Optimización de políticas (advisors de rendimiento de Supabase). Pendiente de aplicar.

-- ─── Políticas: sin superposiciones, solo para usuarios autenticados ─────────
drop policy planes_lectura on public.planes;
drop policy planes_admin   on public.planes;
create policy planes_lectura    on public.planes for select to authenticated using (true);
create policy planes_insertar   on public.planes for insert to authenticated with check (privado.es_admin_plataforma(array['super_admin']));
create policy planes_editar     on public.planes for update to authenticated using (privado.es_admin_plataforma(array['super_admin']));
create policy planes_borrar     on public.planes for delete to authenticated using (privado.es_admin_plataforma(array['super_admin']));

drop policy admins_lectura on public.admins_plataforma;
create policy admins_lectura on public.admins_plataforma for select to authenticated using (privado.es_admin_plataforma());

drop policy empresas_lectura on public.empresas;
drop policy empresas_dueno   on public.empresas;
drop policy empresas_admin   on public.empresas;
create policy empresas_lectura  on public.empresas for select to authenticated using (privado.es_miembro(id) or privado.es_admin_plataforma());
create policy empresas_insertar on public.empresas for insert to authenticated with check (privado.es_admin_plataforma(array['super_admin']));
create policy empresas_editar   on public.empresas for update to authenticated using (privado.es_miembro(id, array['dueno']) or privado.es_admin_plataforma(array['super_admin']));
create policy empresas_borrar   on public.empresas for delete to authenticated using (privado.es_admin_plataforma(array['super_admin']));

drop policy suscripciones_lectura on public.suscripciones;
drop policy suscripciones_admin   on public.suscripciones;
create policy suscripciones_lectura  on public.suscripciones for select to authenticated using (privado.es_miembro(empresa_id) or privado.es_admin_plataforma());
create policy suscripciones_insertar on public.suscripciones for insert to authenticated with check (privado.es_admin_plataforma(array['super_admin', 'contabilidad']));
create policy suscripciones_editar   on public.suscripciones for update to authenticated using (privado.es_admin_plataforma(array['super_admin', 'contabilidad']));
create policy suscripciones_borrar   on public.suscripciones for delete to authenticated using (privado.es_admin_plataforma(array['super_admin']));

drop policy cobros_lectura on public.cobros_suscripcion;
drop policy cobros_admin   on public.cobros_suscripcion;
create policy cobros_lectura  on public.cobros_suscripcion for select to authenticated using (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma());
create policy cobros_insertar on public.cobros_suscripcion for insert to authenticated with check (privado.es_admin_plataforma(array['super_admin', 'contabilidad']));
create policy cobros_editar   on public.cobros_suscripcion for update to authenticated using (privado.es_admin_plataforma(array['super_admin', 'contabilidad']));
create policy cobros_borrar   on public.cobros_suscripcion for delete to authenticated using (privado.es_admin_plataforma(array['super_admin']));

drop policy miembros_lectura on public.miembros;
drop policy miembros_dueno   on public.miembros;
create policy miembros_lectura  on public.miembros for select to authenticated using (privado.es_miembro(empresa_id) or privado.es_admin_plataforma());
create policy miembros_insertar on public.miembros for insert to authenticated with check (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma(array['super_admin', 'soporte']));
create policy miembros_editar   on public.miembros for update to authenticated using (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma(array['super_admin', 'soporte']));
create policy miembros_borrar   on public.miembros for delete to authenticated using (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma(array['super_admin', 'soporte']));

do $$
declare t text;
begin
  foreach t in array array['propiedades', 'unidades', 'contratos', 'documentos', 'interesados'] loop
    execute format('alter policy %1$s_lectura on public.%1$I to authenticated', t);
    execute format('alter policy %1$s_insertar on public.%1$I to authenticated', t);
    execute format('alter policy %1$s_editar on public.%1$I to authenticated', t);
    execute format('alter policy %1$s_borrar on public.%1$I to authenticated', t);
  end loop;
end $$;
alter policy pagos_lectura  on public.pagos to authenticated;
alter policy pagos_insertar on public.pagos to authenticated;
alter policy pagos_editar   on public.pagos to authenticated;
alter policy pagos_borrar   on public.pagos to authenticated;

drop policy bitacora_lectura  on public.bitacora;
drop policy bitacora_insertar on public.bitacora;
create policy bitacora_lectura  on public.bitacora for select to authenticated using (privado.es_miembro(empresa_id, array['dueno']) or privado.es_admin_plataforma());
create policy bitacora_insertar on public.bitacora for insert to authenticated with check (
  user_id = (select auth.uid()) and (privado.es_miembro(empresa_id) or (empresa_id is null and privado.es_admin_plataforma())));

-- ─── Índices de llaves foráneas ──────────────────────────────────────────────
create index on public.bitacora (user_id);
create index on public.documentos (autor);
create index on public.documentos (unidad_id);
create index on public.interesados (por);
create index on public.interesados (unidad_id);
create index on public.miembros (user_id);
create index on public.pagos (registrado_por);
create index on public.suscripciones (plan_id);
create index on public.unidades (propiedad_id);
