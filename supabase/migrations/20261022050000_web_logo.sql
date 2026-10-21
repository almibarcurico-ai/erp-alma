-- Logo de la inmobiliaria en la página web (URL en Storage guardada en empresas.web->>'logo')
create or replace function public.web_inmobiliaria(p_slug text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'empresa', jsonb_build_object(
      'nombre', e.nombre,
      'titulo', coalesce(nullif(e.web->>'titulo', ''), e.nombre),
      'descripcion', e.web->>'descripcion',
      'color', e.web->>'color',
      'logo', nullif(e.web->>'logo', ''),
      'whatsapp', coalesce(nullif(e.web->>'whatsapp', ''), e.telefono),
      'email', coalesce(nullif(e.web->>'email', ''), e.email)),
    'propiedades', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.id, 'propiedad', x.propiedad, 'es_centro', x.es_centro, 'unidad', x.unidad, 'categoria', x.categoria,
        'comuna', x.comuna, 'ciudad', x.ciudad, 'lat', x.lat, 'lng', x.lng,
        'm2', x.m2, 'dormitorios', x.dormitorios, 'banos', x.banos, 'estacionamientos', x.estacionamientos,
        'descripcion', x.descripcion, 'operacion', x.operacion, 'precio_uf', x.precio_uf, 'precio_venta_uf', x.precio_venta_uf,
        'gastos_comunes', x.gastos_comunes, 'fotos', x.fotos, 'disponible', x.disponible)
        order by not x.disponible, x.comuna, x.propiedad, x.orden)
      from (
        select u.id, p.nombre as propiedad, p.tipo = 'centro' as es_centro, u.nombre as unidad, u.categoria,
               p.comuna, p.ciudad,
               -- ubicación aproximada (~100 m): la dirección exacta no se publica
               round(p.lat::numeric, 3) as lat, round(p.lng::numeric, 3) as lng,
               u.m2, u.dormitorios, u.banos, u.estacionamientos, u.descripcion, u.operacion, u.precio_uf, u.precio_venta_uf,
               case when (u.servicios->'gastoComun'->>'aplica')::boolean then u.servicios->'gastoComun'->>'montoAprox' end as gastos_comunes,
               u.fotos, u.orden,
               not exists (select 1 from contratos c where c.unidad_id = u.id and c.vigente) as disponible
        from unidades u join propiedades p on p.id = u.propiedad_id
        where u.empresa_id = e.id and u.publicar) x), '[]'::jsonb))
  from empresas e join suscripciones s on s.empresa_id = e.id
  where e.slug = lower(trim(p_slug))
    and coalesce((e.web->>'activa')::boolean, false)
    and s.estado in ('prueba', 'activa', 'morosa')
$$;
