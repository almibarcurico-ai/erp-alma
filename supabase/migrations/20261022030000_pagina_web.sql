-- Página web pública de cada inmobiliaria: muestra solo las unidades sin contrato vigente
-- marcadas para publicar. El público (anon) no lee tablas: solo llama a dos funciones que
-- devuelven datos seleccionados (sin arrendadores, contratos ni dirección exacta) y que
-- registran a los interesados del formulario de contacto.

alter table public.empresas
  add column slug text unique check (slug ~ '^[a-z0-9]+(-[a-z0-9]+)*$' and length(slug) between 3 and 40),
  add column web  jsonb not null default '{}';     -- activa, titulo, descripcion, color, whatsapp, email

alter table public.unidades
  add column publicar        boolean not null default true,
  add column operacion       text not null default 'arriendo' check (operacion in ('arriendo', 'venta', 'ambas')),
  add column precio_venta_uf numeric(12,2);

-- Datos públicos de la inmobiliaria y sus propiedades disponibles
create or replace function public.web_inmobiliaria(p_slug text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'empresa', jsonb_build_object(
      'nombre', e.nombre,
      'titulo', coalesce(nullif(e.web->>'titulo', ''), e.nombre),
      'descripcion', e.web->>'descripcion',
      'color', e.web->>'color',
      'whatsapp', coalesce(nullif(e.web->>'whatsapp', ''), e.telefono),
      'email', coalesce(nullif(e.web->>'email', ''), e.email)),
    'propiedades', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', u.id, 'propiedad', p.nombre, 'es_centro', p.tipo = 'centro', 'unidad', u.nombre, 'categoria', u.categoria,
        'comuna', p.comuna, 'ciudad', p.ciudad,
        -- ubicación aproximada (~100 m): la dirección exacta no se publica
        'lat', round(p.lat::numeric, 3), 'lng', round(p.lng::numeric, 3),
        'm2', u.m2, 'dormitorios', u.dormitorios, 'banos', u.banos, 'estacionamientos', u.estacionamientos,
        'descripcion', u.descripcion, 'operacion', u.operacion, 'precio_uf', u.precio_uf, 'precio_venta_uf', u.precio_venta_uf,
        'gastos_comunes', case when (u.servicios->'gastoComun'->>'aplica')::boolean then u.servicios->'gastoComun'->>'montoAprox' end,
        'fotos', u.fotos)
        order by p.comuna, p.nombre, u.orden)
      from unidades u join propiedades p on p.id = u.propiedad_id
      where u.empresa_id = e.id and u.publicar
        and not exists (select 1 from contratos c where c.unidad_id = u.id and c.vigente)), '[]'::jsonb))
  from empresas e join suscripciones s on s.empresa_id = e.id
  where e.slug = lower(trim(p_slug))
    and coalesce((e.web->>'activa')::boolean, false)
    and s.estado in ('prueba', 'activa', 'morosa')
$$;
revoke execute on function public.web_inmobiliaria(text) from public;
grant execute on function public.web_inmobiliaria(text) to anon, authenticated;

-- Formulario "Me interesa": crea un interesado en la unidad (aparece en la ficha y la bitácora)
create or replace function public.web_contacto(p_slug text, p_unidad uuid, p_nombre text, p_telefono text, p_email text, p_mensaje text)
returns void language plpgsql security definer set search_path = public as $$
declare e uuid; nombre text := left(trim(coalesce(p_nombre, '')), 100);
        tel text := left(trim(coalesce(p_telefono, '')), 30); correo text := left(lower(trim(coalesce(p_email, ''))), 120);
begin
  select em.id into e from empresas em join unidades u on u.empresa_id = em.id join suscripciones s on s.empresa_id = em.id
   where em.slug = lower(trim(p_slug)) and coalesce((em.web->>'activa')::boolean, false) and s.estado in ('prueba', 'activa', 'morosa')
     and u.id = p_unidad and u.publicar
     and not exists (select 1 from contratos c where c.unidad_id = u.id and c.vigente);
  if e is null then raise exception 'Propiedad no disponible'; end if;
  if length(nombre) < 2 then raise exception 'Ingresa tu nombre'; end if;
  if tel = '' and correo = '' then raise exception 'Ingresa un teléfono o correo'; end if;
  if correo <> '' and correo !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'Correo inválido'; end if;
  -- límite simple contra abuso: 30 contactos por hora por inmobiliaria
  if (select count(*) from interesados where empresa_id = e and canal = 'Sitio web' and creado > now() - interval '1 hour') >= 30 then
    raise exception 'Demasiadas solicitudes. Intenta más tarde.';
  end if;
  insert into interesados (empresa_id, unidad_id, nombre, telefono, email, nota, canal, por_nombre)
  values (e, p_unidad, nombre, nullif(tel, ''), nullif(correo, ''),
          coalesce(nullif(left(trim(coalesce(p_mensaje, '')), 1000), ''), 'Pidió información desde la página web'), 'Sitio web', 'Sitio web');
  insert into bitacora (empresa_id, usuario, accion)
  select e, 'Sitio web', 'Nuevo interesado desde la web: ' || nombre || ' (' || (select case when p.tipo = 'centro' then p.nombre || ' · ' || u.nombre else p.nombre end
    from unidades u join propiedades p on p.id = u.propiedad_id where u.id = p_unidad) || ')';
end $$;
revoke execute on function public.web_contacto(text, uuid, text, text, text, text) from public;
grant execute on function public.web_contacto(text, uuid, text, text, text, text) to anon, authenticated;
