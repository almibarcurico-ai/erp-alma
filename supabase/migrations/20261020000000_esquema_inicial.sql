-- Qipo Arriendos · esquema SaaS multi-empresa
-- Cada empresa cliente (corredora, administradora o propietario) es un "tenant".
-- Los usuarios ven solo los datos de las empresas de las que son miembros (RLS).
-- Los administradores de plataforma (Torre de Control HM) ven y administran todo.

create extension if not exists pgcrypto;

-- ─── Plataforma ──────────────────────────────────────────────────────────────

create table public.planes (
  id           text primary key,                -- 'propietario', 'corredor', 'pro', 'empresa'
  nombre       text not null,
  max_unidades int,                             -- null = sin límite
  precio_uf    numeric(8,3) not null,           -- precio mensual base
  uf_por_unidad numeric(8,4),                   -- plan empresa: precio por unidad sobre el mínimo
  activo       boolean not null default true
);

insert into public.planes (id, nombre, max_unidades, precio_uf, uf_por_unidad) values
  ('propietario', 'Propietario', 10,   0.5,  null),
  ('corredor',    'Corredor',    50,   1.75, null),
  ('pro',         'Pro',         150,  4.5,  null),
  ('empresa',     'Empresa',     null, 4.5,  0.025);

create table public.admins_plataforma (
  user_id uuid primary key references auth.users on delete cascade,
  rol     text not null check (rol in ('super_admin', 'contabilidad', 'soporte')),
  creado  timestamptz not null default now()
);

create table public.empresas (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  rut        text,
  email      text,
  telefono   text,
  direccion  text,
  representante text,
  rut_rep    text,
  notas      text,
  creado     timestamptz not null default now()
);

create table public.suscripciones (
  empresa_id   uuid primary key references public.empresas on delete cascade,
  plan_id      text not null references public.planes,
  estado       text not null default 'prueba' check (estado in ('prueba', 'activa', 'morosa', 'suspendida', 'cancelada')),
  prueba_hasta date,
  vigente_hasta date,
  precio_uf_pactado numeric(8,3),               -- precio especial; null = precio del plan
  actualizado  timestamptz not null default now()
);

create table public.cobros_suscripcion (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas on delete cascade,
  periodo     text not null check (periodo ~ '^\d{4}-\d{2}$'),
  monto_uf    numeric(8,3) not null,
  uf_dia      numeric(10,2),
  monto_clp   integer,
  estado      text not null default 'pendiente' check (estado in ('pendiente', 'pagado', 'anulado')),
  pagado_en   date,
  medio       text,
  creado      timestamptz not null default now(),
  unique (empresa_id, periodo)
);

create table public.miembros (
  empresa_id uuid not null references public.empresas on delete cascade,
  user_id    uuid not null references auth.users on delete cascade,
  nombre     text not null,
  rol        text not null check (rol in ('dueno', 'secretaria')),
  activo     boolean not null default true,
  primary key (empresa_id, user_id)
);

-- ─── Operación de cada empresa ───────────────────────────────────────────────

create table public.propiedades (
  id         uuid primary key default gen_random_uuid(),
  empresa_id uuid not null references public.empresas on delete cascade,
  tipo       text not null check (tipo in ('propiedad', 'centro')),
  nombre     text not null,
  direccion  text,
  comuna     text,
  ciudad     text,
  lat        double precision not null,
  lng        double precision not null,
  rol_sii    text,
  notas      text,
  arrendador jsonb not null default '{}',       -- vacío = la empresa es la arrendadora
  creado     timestamptz not null default now()
);

create table public.unidades (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas on delete cascade,
  propiedad_id uuid not null references public.propiedades on delete cascade,
  nombre      text not null,
  categoria   text not null default 'otro',
  m2          numeric, dormitorios int, banos int, estacionamientos int,
  descripcion text,
  precio_uf   numeric(10,3),
  fotos       text[] not null default '{}'      -- rutas en Storage (bucket "fotos")
);

create table public.contratos (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas on delete cascade,
  unidad_id   uuid not null references public.unidades on delete cascade,
  arrendatario jsonb not null,                  -- nombre, rut, email, telefono, giro, domicilio, representante
  inicio      date not null,
  termino     date,
  dia_pago    int not null check (dia_pago between 1 and 31),
  moneda      text not null default 'UF' check (moneda in ('UF', 'CLP')),
  valor       numeric(12,3) not null,
  garantia    numeric(12,3),
  multa       jsonb not null default '{"cobrar": false}', -- cobrar, tipo, monto, diasGracia, tope
  multas_condonadas text[] not null default '{}',          -- periodos 'YYYY-MM'
  vigente     boolean not null default true,
  terminado   date
);
create unique index contrato_vigente_por_unidad on public.contratos (unidad_id) where vigente;

create table public.pagos (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas on delete cascade,
  contrato_id uuid not null references public.contratos on delete cascade,
  periodo     text not null check (periodo ~ '^\d{4}-\d{2}$'),
  fecha       date not null,
  uf_dia      numeric(10,2),
  monto_clp   integer not null,
  multa_clp   integer not null default 0,
  medio       text,
  obs         text,
  registrado_por uuid references auth.users,
  creado      timestamptz not null default now(),
  unique (contrato_id, periodo)
);

create table public.documentos (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas on delete cascade,
  unidad_id   uuid not null references public.unidades on delete cascade,
  tipo        text not null,
  titulo      text not null,
  html        text not null,
  autor       uuid references auth.users,
  creado      timestamptz not null default now()
);

create table public.interesados (
  id          uuid primary key default gen_random_uuid(),
  empresa_id  uuid not null references public.empresas on delete cascade,
  unidad_id   uuid not null references public.unidades on delete cascade,
  nombre text, telefono text, email text, nota text, canal text,
  por         uuid references auth.users,
  creado      timestamptz not null default now()
);

create table public.bitacora (
  id          bigserial primary key,
  empresa_id  uuid references public.empresas on delete cascade,  -- null = acción de plataforma
  user_id     uuid references auth.users,
  usuario     text,
  accion      text not null,
  creado      timestamptz not null default now()
);

-- ─── Funciones de acceso ─────────────────────────────────────────────────────

create or replace function public.es_admin_plataforma(roles text[] default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from admins_plataforma a
                 where a.user_id = auth.uid() and (roles is null or a.rol = any(roles)));
$$;

create or replace function public.es_miembro(e uuid, roles text[] default null)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from miembros m
                 where m.empresa_id = e and m.user_id = auth.uid() and m.activo
                   and (roles is null or m.rol = any(roles)));
$$;

-- Una empresa suspendida o cancelada no puede operar
create or replace function public.empresa_operativa(e uuid)
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from suscripciones s where s.empresa_id = e
                 and s.estado in ('prueba', 'activa', 'morosa'));
$$;

-- ─── RLS ─────────────────────────────────────────────────────────────────────

alter table public.planes             enable row level security;
alter table public.admins_plataforma  enable row level security;
alter table public.empresas           enable row level security;
alter table public.suscripciones      enable row level security;
alter table public.cobros_suscripcion enable row level security;
alter table public.miembros           enable row level security;
alter table public.propiedades        enable row level security;
alter table public.unidades           enable row level security;
alter table public.contratos          enable row level security;
alter table public.pagos              enable row level security;
alter table public.documentos         enable row level security;
alter table public.interesados        enable row level security;
alter table public.bitacora           enable row level security;

create policy planes_lectura on public.planes for select using (auth.uid() is not null);
create policy planes_admin   on public.planes for all using (es_admin_plataforma(array['super_admin']));

create policy admins_lectura on public.admins_plataforma for select using (es_admin_plataforma());

create policy empresas_lectura on public.empresas for select using (es_miembro(id) or es_admin_plataforma());
create policy empresas_dueno   on public.empresas for update using (es_miembro(id, array['dueno']));
create policy empresas_admin   on public.empresas for all using (es_admin_plataforma(array['super_admin']));

create policy suscripciones_lectura on public.suscripciones for select using (es_miembro(empresa_id) or es_admin_plataforma());
create policy suscripciones_admin   on public.suscripciones for all using (es_admin_plataforma(array['super_admin', 'contabilidad']));

create policy cobros_lectura on public.cobros_suscripcion for select using (es_miembro(empresa_id, array['dueno']) or es_admin_plataforma());
create policy cobros_admin   on public.cobros_suscripcion for all using (es_admin_plataforma(array['super_admin', 'contabilidad']));

create policy miembros_lectura on public.miembros for select using (es_miembro(empresa_id) or es_admin_plataforma());
create policy miembros_dueno   on public.miembros for all using (es_miembro(empresa_id, array['dueno']) or es_admin_plataforma(array['super_admin', 'soporte']));

-- Datos operativos: miembros activos de una empresa operativa; la plataforma solo lee
do $$
declare t text;
begin
  foreach t in array array['propiedades', 'unidades', 'contratos', 'documentos', 'interesados'] loop
    execute format('create policy %1$s_lectura on public.%1$I for select using (es_miembro(empresa_id) or es_admin_plataforma())', t);
    execute format('create policy %1$s_insertar on public.%1$I for insert with check (es_miembro(empresa_id) and empresa_operativa(empresa_id))', t);
    execute format('create policy %1$s_editar on public.%1$I for update using (es_miembro(empresa_id) and empresa_operativa(empresa_id))', t);
    execute format('create policy %1$s_borrar on public.%1$I for delete using (es_miembro(empresa_id, array[''dueno'']) and empresa_operativa(empresa_id))', t);
  end loop;
end $$;

-- Pagos: la secretaria registra; solo el dueño corrige o elimina
create policy pagos_lectura  on public.pagos for select using (es_miembro(empresa_id) or es_admin_plataforma());
create policy pagos_insertar on public.pagos for insert with check (es_miembro(empresa_id) and empresa_operativa(empresa_id));
create policy pagos_editar   on public.pagos for update using (es_miembro(empresa_id, array['dueno']));
create policy pagos_borrar   on public.pagos for delete using (es_miembro(empresa_id, array['dueno']));

-- Bitácora: solo se agrega, nunca se edita
create policy bitacora_lectura  on public.bitacora for select using (es_miembro(empresa_id, array['dueno']) or es_admin_plataforma());
create policy bitacora_insertar on public.bitacora for insert with check (
  user_id = auth.uid() and (es_miembro(empresa_id) or (empresa_id is null and es_admin_plataforma())));

-- Solo el dueño activa, desactiva o condona multas
create or replace function public.proteger_multa() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.multa is distinct from old.multa or new.multas_condonadas is distinct from old.multas_condonadas)
     and not es_miembro(new.empresa_id, array['dueno']) then
    raise exception 'Solo el dueño puede cambiar o condonar multas';
  end if;
  return new;
end $$;
create trigger contratos_proteger_multa before update on public.contratos
  for each row execute function public.proteger_multa();

-- ─── Vista para la Torre de Control HM ───────────────────────────────────────

create or replace view public.torre_empresas with (security_invoker = true) as
select e.id, e.nombre, e.rut, e.email, e.telefono, e.creado,
       s.plan_id, p.nombre as plan, s.estado, s.prueba_hasta, s.vigente_hasta,
       (select count(*) from unidades u where u.empresa_id = e.id) as unidades,
       (select count(*) from contratos c where c.empresa_id = e.id and c.vigente) as ocupadas,
       coalesce(s.precio_uf_pactado,
                p.precio_uf + coalesce(p.uf_por_unidad, 0)
                  * greatest(0, (select count(*) from unidades u where u.empresa_id = e.id) - 150)) as mrr_uf,
       (select count(*) from cobros_suscripcion cs where cs.empresa_id = e.id and cs.estado = 'pendiente') as cobros_pendientes,
       (select max(m.creado) from bitacora m where m.empresa_id = e.id) as ultima_actividad
from empresas e
left join suscripciones s on s.empresa_id = e.id
left join planes p on p.id = s.plan_id;

-- Índices de acceso por empresa
create index on public.propiedades (empresa_id);
create index on public.unidades (empresa_id, propiedad_id);
create index on public.contratos (empresa_id, unidad_id);
create index on public.pagos (empresa_id, contrato_id);
create index on public.documentos (empresa_id, unidad_id);
create index on public.interesados (empresa_id, unidad_id);
create index on public.bitacora (empresa_id, creado desc);
create index on public.cobros_suscripcion (empresa_id, periodo);
