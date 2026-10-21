-- Acceso de soporte: los administradores de plataforma (super_admin y soporte) entran a cualquier
-- inmobiliaria con los mismos permisos que su dueño, sin ser miembros (no ocupan cupo de usuarios).
-- Lo que hagan queda en la bitácora de la empresa con su nombre de soporte. Contabilidad no entra.
create or replace function privado.es_miembro(e uuid, roles text[] default null) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros m
                 where m.empresa_id = e and m.user_id = auth.uid() and m.activo
                   and (roles is null or m.rol = any(roles)))
      or exists (select 1 from admins_plataforma a
                 where a.user_id = auth.uid() and a.rol in ('super_admin', 'soporte'))
$$;
