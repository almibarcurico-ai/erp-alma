-- Pangoa: reactivar el "Descuento Convenio 40% cocina" (13-sep-2026).
--
-- En servicio real Pangoa sigue usando el Convenio (mesa 18, orden 3428:
-- "Imprime sin descuento... cobraremos con foto"). El guard del 01-sep
-- (trg_pangoa_guard_convenio) contradecia la operacion: bloqueaba aplicar el
-- descuento y, con el arreglo de hoy, imprimia la precuenta sin el.
--
-- Se quita el trigger. La funcion pangoa_guard_convenio_descontinuado() se
-- conserva por si administracion decide volver a descontinuarlo:
--   create trigger trg_pangoa_guard_convenio before insert or update on public.orders
--     for each row execute function public.pangoa_guard_convenio_descontinuado();
--
-- Con el trigger fuera, el flujo queda como antes del 01-sep: el POS persiste
-- el breakdown con la linea Convenio, la precuenta sale con el descuento y la
-- propina sugerida se calcula sobre el subtotal sin descuento
-- (migracion pangoa_convenio_tip_pre_descuento, 15-ago-2026).
--
-- Aplicada en produccion como migracion `pangoa_reactivar_convenio`.

drop trigger if exists trg_pangoa_guard_convenio on public.orders;

comment on function public.pangoa_guard_convenio_descontinuado() is
  'Pangoa: guard del Descuento Convenio. SIN TRIGGER desde 13-sep-2026 (Convenio reactivado). Para volver a descontinuarlo, recrear trg_pangoa_guard_convenio sobre public.orders.';
