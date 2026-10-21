-- Abonos: pagos parciales de un mes. Un mes queda pagado con un registro en pagos
-- o cuando la suma de sus abonos cubre la renta del mes (con IVA si corresponde).
create table public.abonos (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas on delete cascade,
  contrato_id uuid not null references public.contratos on delete cascade,
  periodo     text not null check (periodo ~ '^\d{4}-\d{2}$'),
  fecha       date not null,
  uf_dia      numeric(10,2),
  monto_clp   integer not null check (monto_clp > 0),
  medio       text,
  obs         text,
  registrado_nombre text,
  creado      timestamptz not null default now()
);
create index on public.abonos (empresa_id, contrato_id);
create index on public.abonos (contrato_id, periodo);

alter table public.abonos enable row level security;
-- Igual que pagos: la secretaria registra; solo el dueño corrige o elimina
create policy abonos_lectura  on public.abonos for select to authenticated using (privado.es_miembro(empresa_id) or privado.es_admin_plataforma());
create policy abonos_insertar on public.abonos for insert to authenticated with check (privado.es_miembro(empresa_id) and privado.empresa_operativa(empresa_id));
create policy abonos_editar   on public.abonos for update to authenticated using (privado.es_miembro(empresa_id, array['dueno']));
create policy abonos_borrar   on public.abonos for delete to authenticated using (privado.es_miembro(empresa_id, array['dueno']));

alter publication supabase_realtime add table public.abonos;
