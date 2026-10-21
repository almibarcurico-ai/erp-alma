-- Planes con precio en pesos, usuarios máximos y funciones; propietarios y liquidaciones para corredoras.

-- ─── Planes ──────────────────────────────────────────────────────────────────
-- precio_clp: mensual, neto (+ IVA). Pago anual = 10 meses (2 gratis).
-- funciones: 'propietarios' (propietarios y liquidaciones), 'exportar' (Excel/CSV), 'soporte_prioritario'.
alter table public.planes
  add column precio_clp   integer,
  add column max_usuarios integer,                -- null = sin límite
  add column funciones    text[] not null default '{}',
  add column orden        integer not null default 0;
alter table public.planes alter column precio_uf drop not null;

update public.planes set nombre = 'Propietario', precio_clp = 14900,  max_unidades = 10,  max_usuarios = 2,  funciones = '{}', orden = 1, precio_uf = null, uf_por_unidad = null where id = 'propietario';
update public.planes set nombre = 'Corredor',    precio_clp = 39900,  max_unidades = 50,  max_usuarios = 3,  funciones = '{propietarios}', orden = 2, precio_uf = null, uf_por_unidad = null where id = 'corredor';
update public.planes set nombre = 'Profesional', precio_clp = 79900,  max_unidades = 200, max_usuarios = 8,  funciones = '{propietarios,exportar}', orden = 3, precio_uf = null, uf_por_unidad = null where id = 'pro';
update public.planes set nombre = 'Empresa',     precio_clp = 149900, max_unidades = 600, max_usuarios = 20, funciones = '{propietarios,exportar,soporte_prioritario}', orden = 4, precio_uf = null, uf_por_unidad = null where id = 'empresa';
alter table public.planes alter column precio_clp set not null;

-- Precio especial (plan corporativo o descuento) y ciclo de pago
alter table public.suscripciones
  add column precio_clp_pactado integer,
  add column ciclo text not null default 'mensual' check (ciclo in ('mensual', 'anual'));

-- ¿El plan de la empresa incluye la función? Durante la prueba se habilita todo.
create or replace function privado.plan_permite(e uuid, funcion text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from suscripciones s join planes p on p.id = s.plan_id
    where s.empresa_id = e and (s.estado = 'prueba' or funcion = any(p.funciones)))
$$;
revoke execute on function privado.plan_permite(uuid, text) from public, anon;
grant execute on function privado.plan_permite(uuid, text) to authenticated;

-- Usuarios máximos: miembros activos + invitaciones pendientes
create or replace function privado.limitar_usuarios() returns trigger
language plpgsql security definer set search_path = public as $$
declare maximo int;
begin
  select p.max_usuarios into maximo from suscripciones s join planes p on p.id = s.plan_id where s.empresa_id = new.empresa_id;
  if maximo is not null and
     (select count(*) from miembros where empresa_id = new.empresa_id and activo)
     + (select count(*) from invitaciones where empresa_id = new.empresa_id and aceptada is null) >= maximo then
    raise exception 'Tu plan permite hasta % usuarios. Cambia de plan para invitar a más.', maximo;
  end if;
  return new;
end $$;
revoke execute on function privado.limitar_usuarios() from public, anon, authenticated;
create trigger invitaciones_limite before insert on public.invitaciones
  for each row execute function privado.limitar_usuarios();

-- ─── Propietarios ────────────────────────────────────────────────────────────
-- Dueños de las propiedades que administra la corredora. La secretaria ve nombre y contacto;
-- crear, editar y los datos bancarios (tabla aparte) son solo del dueño de la empresa.
create table public.propietarios (
  id           uuid primary key default gen_random_uuid(),
  empresa_id   uuid not null references public.empresas on delete cascade,
  nombre       text not null,
  rut          text,
  email        text,
  telefono     text,
  domicilio    text,
  representante text,                            -- si el propietario es una sociedad
  rut_rep      text,
  comision_pct numeric(5,2) not null default 0 check (comision_pct between 0 and 100),
  comision_iva boolean not null default true,     -- la comisión de administración se factura con IVA
  notas        text,
  creado       timestamptz not null default now(),
  unique (empresa_id, id)
);
create index on public.propietarios (empresa_id);

-- La propiedad solo puede apuntar a un propietario de su misma empresa
alter table public.propiedades add column propietario_id uuid;
alter table public.propiedades add constraint propiedades_propietario_fk
  foreign key (empresa_id, propietario_id) references public.propietarios (empresa_id, id) on delete set null (propietario_id);
create index on public.propiedades (empresa_id, propietario_id);

alter table public.propietarios enable row level security;
create policy propietarios_lectura  on public.propietarios for select to authenticated using (privado.es_miembro(empresa_id));
create policy propietarios_insertar on public.propietarios for insert to authenticated
  with check (privado.es_miembro(empresa_id, array['dueno']) and privado.empresa_operativa(empresa_id) and privado.plan_permite(empresa_id, 'propietarios'));
create policy propietarios_editar   on public.propietarios for update to authenticated using (privado.es_miembro(empresa_id, array['dueno']));
create policy propietarios_borrar   on public.propietarios for delete to authenticated using (privado.es_miembro(empresa_id, array['dueno']));

create table public.propietarios_banco (
  id         uuid primary key,                   -- mismo id del propietario
  empresa_id uuid not null,
  datos      jsonb not null default '{}',        -- banco, tipo, numero, titular, rut
  foreign key (empresa_id, id) references public.propietarios (empresa_id, id) on delete cascade
);
alter table public.propietarios_banco enable row level security;
create policy propietarios_banco_lectura  on public.propietarios_banco for select to authenticated using (privado.es_miembro(empresa_id, array['dueno']));
create policy propietarios_banco_insertar on public.propietarios_banco for insert to authenticated with check (privado.es_miembro(empresa_id, array['dueno']) and privado.empresa_operativa(empresa_id));
create policy propietarios_banco_editar   on public.propietarios_banco for update to authenticated using (privado.es_miembro(empresa_id, array['dueno']));
create policy propietarios_banco_borrar   on public.propietarios_banco for delete to authenticated using (privado.es_miembro(empresa_id, array['dueno']));

-- ─── Liquidaciones ───────────────────────────────────────────────────────────
-- Rendición mensual al propietario: lo cobrado en el mes (por fecha de pago) menos la comisión
-- de administración (+ IVA) y los descuentos. Una vez emitida no se modifica: solo se marca
-- pagada o se anula (y se emite otra).
create table public.liquidaciones (
  id             uuid primary key default gen_random_uuid(),
  empresa_id     uuid not null references public.empresas on delete cascade,
  propietario_id uuid not null,
  periodo        text not null check (periodo ~ '^\d{4}-\d{2}$'),
  detalle        jsonb not null,                 -- cobros (con id de pago/abono), descuentos, comisión %
  total_cobrado  integer not null,
  comision       integer not null,
  iva_comision   integer not null,
  descuentos     integer not null,
  total          integer not null,
  estado         text not null default 'emitida' check (estado in ('emitida', 'pagada', 'anulada')),
  pagada_en      date,
  medio          text,
  emitida_por    text,
  creado         timestamptz not null default now(),
  foreign key (empresa_id, propietario_id) references public.propietarios (empresa_id, id) on delete restrict
);
create unique index liquidaciones_una_por_mes on public.liquidaciones (empresa_id, propietario_id, periodo) where estado <> 'anulada';
create index on public.liquidaciones (empresa_id, periodo);

create or replace function privado.proteger_liquidacion() returns trigger
language plpgsql as $$
begin
  if old.estado = 'anulada' then raise exception 'La liquidación está anulada'; end if;
  if (to_jsonb(new) - array['estado', 'pagada_en', 'medio']) <> (to_jsonb(old) - array['estado', 'pagada_en', 'medio']) then
    raise exception 'Una liquidación emitida no se modifica: anúlala y emite otra';
  end if;
  return new;
end $$;
create trigger liquidaciones_proteger before update on public.liquidaciones
  for each row execute function privado.proteger_liquidacion();

alter table public.liquidaciones enable row level security;
create policy liquidaciones_lectura  on public.liquidaciones for select to authenticated using (privado.es_miembro(empresa_id, array['dueno']));
create policy liquidaciones_insertar on public.liquidaciones for insert to authenticated
  with check (privado.es_miembro(empresa_id, array['dueno']) and privado.empresa_operativa(empresa_id) and privado.plan_permite(empresa_id, 'propietarios'));
create policy liquidaciones_editar   on public.liquidaciones for update to authenticated using (privado.es_miembro(empresa_id, array['dueno']));

alter publication supabase_realtime add table public.propietarios, public.liquidaciones;

-- ─── Torre de Control: ingreso mensual en pesos ──────────────────────────────
create or replace view public.torre_empresas with (security_invoker = true) as
select e.id, e.nombre, e.rut, e.email, e.telefono, e.creado,
       s.plan_id, p.nombre as plan, s.estado, s.prueba_hasta, s.vigente_hasta,
       (select count(*) from unidades u where u.empresa_id = e.id) as unidades,
       (select count(*) from contratos c where c.empresa_id = e.id and c.vigente) as ocupadas,
       s.precio_uf_pactado::numeric as mrr_uf,
       (select count(*) from cobros_suscripcion cs where cs.empresa_id = e.id and cs.estado = 'pendiente') as cobros_pendientes,
       (select max(m.creado) from bitacora m where m.empresa_id = e.id) as ultima_actividad,
       coalesce(s.precio_clp_pactado, p.precio_clp) as mrr_clp,
       s.ciclo
from empresas e
left join suscripciones s on s.empresa_id = e.id
left join planes p on p.id = s.plan_id;
