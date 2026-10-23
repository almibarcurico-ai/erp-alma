-- Fotos del inventario (interior, llaves, artefactos) en un bucket privado: solo los miembros de la
-- empresa (o Soporte HM con acceso abierto) las ven, mediante enlaces firmados de 1 hora.
-- Las fotos de la propiedad siguen en el bucket público "fotos" porque se comparten y publican.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('privado', 'privado', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy privado_leer on storage.objects for select to authenticated
  using (bucket_id = 'privado' and privado.es_miembro(privado.empresa_de_ruta(name)));
create policy privado_subir on storage.objects for insert to authenticated
  with check (bucket_id = 'privado' and privado.es_miembro(privado.empresa_de_ruta(name)) and privado.empresa_operativa(privado.empresa_de_ruta(name)));
create policy privado_borrar on storage.objects for delete to authenticated
  using (bucket_id = 'privado' and privado.es_miembro(privado.empresa_de_ruta(name)) and privado.empresa_operativa(privado.empresa_de_ruta(name)));
