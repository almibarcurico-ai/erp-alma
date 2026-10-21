-- search_path fijo en las funciones nuevas (recomendación del linter de Supabase)
alter function privado.empresa_de_ruta(text) set search_path = '';
alter function privado.proteger_liquidacion() set search_path = '';
