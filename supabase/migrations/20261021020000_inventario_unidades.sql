-- Inventario de cada unidad: lista de ítems con recinto, cantidad, estado, notas y fotos.
-- Forma: [{"id": "...", "recinto": "Cocina", "nombre": "Refrigerador", "cantidad": 1,
--          "estado": "bueno", "notas": "...", "fotos": ["data:image/jpeg;base64,..."]}]
alter table public.unidades add column inventario jsonb not null default '[]';
