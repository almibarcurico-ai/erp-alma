-- IVA opcional sobre la renta (p. ej. locales comerciales afectos).
-- contratos.iva: si la renta se cobra más IVA (19%). pagos.iva_clp: IVA incluido en monto_clp.
alter table public.contratos add column iva boolean not null default false;
alter table public.pagos add column iva_clp integer not null default 0;
