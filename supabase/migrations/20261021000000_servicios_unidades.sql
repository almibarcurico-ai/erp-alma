-- Servicios de cada unidad: números de cliente de luz y agua (uno o más por servicio)
-- y gastos comunes cuando la unidad está en un condominio.
-- Forma: {"luz": [{"empresa": "CGE", "cliente": "123"}], "agua": [...],
--         "gastoComun": {"aplica": true, "administracion": "...", "contacto": "...", "montoAprox": 85000, "paga": "arrendatario"}}
alter table public.unidades add column servicios jsonb not null default '{}';
