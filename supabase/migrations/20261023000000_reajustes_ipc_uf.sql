-- Reajustes por IPC o UF: historial de cada reajuste aplicado a un contrato, con el índice usado.
-- Solo agrega una tabla: no toca contratos ni pagos existentes. La configuración del reajuste sigue
-- en contratos.reajuste (jsonb): { tipo: 'ipc'|'uf'|'pct', cadaMeses, pct, primero 'AAAA-MM', avisoDias }.
-- Los contratos antiguos { pct, cadaMeses } se leen como tipo 'pct' y calculan igual que antes.
create table public.reajustes (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas on delete cascade,
  contrato_id    uuid not null references public.contratos on delete cascade,
  desde          text not null check (desde ~ '^\d{4}-\d{2}$'),     -- primer mes con la renta nueva
  tipo           text not null check (tipo in ('ipc', 'uf', 'pct')),
  variacion_pct  numeric(9,4) not null,
  detalle        jsonb not null default '{}',                       -- meses de IPC o valores UF usados
  valor_anterior numeric(12,3) not null,
  valor_nuevo    numeric(12,3) not null check (valor_nuevo >= 0),
  registrado_nombre text,
  creado         timestamptz not null default now(),
  unique (contrato_id, desde)
);
create index on public.reajustes (empresa_id);

alter table public.reajustes enable row level security;
create policy reajustes_lectura on public.reajustes for select to authenticated using (privado.es_miembro(empresa_id));
-- Se registra sobre un contrato de la misma empresa; no se edita (para corregir, el dueño lo borra y se aplica de nuevo)
create policy reajustes_insertar on public.reajustes for insert to authenticated
  with check (privado.es_miembro(empresa_id) and privado.empresa_operativa(empresa_id)
              and exists (select 1 from public.contratos c where c.id = contrato_id and c.empresa_id = reajustes.empresa_id));
create policy reajustes_borrar on public.reajustes for delete to authenticated using (privado.es_miembro(empresa_id, array['dueno']));

alter publication supabase_realtime add table public.reajustes;
