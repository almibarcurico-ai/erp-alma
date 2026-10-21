-- Reajuste opcional de la renta: {"pct": 3, "cadaMeses": 12} sube la renta un 3% cada 12 meses
-- contados desde el mes de inicio del contrato. null = sin reajuste.
alter table public.contratos add column reajuste jsonb;
