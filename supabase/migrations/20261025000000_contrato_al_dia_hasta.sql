-- Contratos que ya venían corriendo al cargarlos: los meses hasta "al día hasta" se dan por pagados
-- (sin registrar cada pago) y no generan deuda. Columna nueva y opcional.
alter table public.contratos add column al_dia_hasta text check (al_dia_hasta ~ '^\d{4}-\d{2}$');
