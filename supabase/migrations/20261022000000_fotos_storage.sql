-- Fotos de unidades e inventario en Supabase Storage (antes iban comprimidas dentro de la base).
-- Ruta de cada archivo: <empresa_id>/<uuid>.jpg. Lectura pública por URL (nombres no adivinables),
-- para que la ficha compartida, el PDF y WhatsApp muestren las fotos; sin listado público.
-- Solo los miembros de la empresa suben o borran en su carpeta.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('fotos', 'fotos', true, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create or replace function privado.empresa_de_ruta(ruta text) returns uuid
language sql immutable as $$
  select case when split_part(ruta, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(ruta, '/', 1)::uuid end
$$;

create policy fotos_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'fotos'
    and privado.es_miembro(privado.empresa_de_ruta(name))
    and privado.empresa_operativa(privado.empresa_de_ruta(name)));
create policy fotos_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'fotos' and privado.es_miembro(privado.empresa_de_ruta(name)));
