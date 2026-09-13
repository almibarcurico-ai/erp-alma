-- Pangoa: el guard del "Descuento Convenio" (descontinuado el 01-sep-2026)
-- bloqueaba el UPDATE completo de la orden. Ese mismo UPDATE es el que el POS
-- usa para pedir la precuenta (notes = 'PRECUENTA_REQUEST'), asi que cuando el
-- garzon elegia el descuento Convenio la precuenta nunca se imprimia
-- (ver postgres logs: "El Descuento Convenio fue descontinuado...").
--
-- Nuevo comportamiento (misma regla de negocio, sin bloquear el servicio):
--   * Se eliminan las lineas "Convenio" de pricing_breakdown.discountLines.
--   * Se recalculan totalDiscount / total / finalTotal / suggestedTip.
--   * Si no queda ninguna linea de descuento, pricing_breakdown queda NULL
--     (igual que una orden sin descuentos automaticos).
--   * orders.total se recalcula: subtotal - descuento manual (porcentaje/monto)
--     - otros descuentos automaticos que sigan vigentes.
--   * El intento queda registrado en order_logs (accion
--     'convenio_descontinuado_ignorado') para que administracion lo vea.
--   * Fail-open: si algo falla dentro del guard, la fila pasa sin cambios.
--
-- Respaldo de la definicion anterior: public._bak_pangoa_guard_convenio_20260913
-- Rollback: ejecutar el `definition` guardado en esa tabla.

create table if not exists public._bak_pangoa_guard_convenio_20260913 as
select now() as backed_up_at, pg_get_functiondef(p.oid) as definition
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
 where n.nspname = 'public' and p.proname = 'pangoa_guard_convenio_descontinuado';
alter table public._bak_pangoa_guard_convenio_20260913 enable row level security;

create or replace function public.pangoa_guard_convenio_descontinuado()
returns trigger
language plpgsql
as $function$
declare
  c_pangoa    constant uuid := '816da88d-56a8-4d0d-81d3-48b1815515ea';
  v_bd        jsonb;
  v_lines     jsonb;
  v_kept      jsonb;
  v_removed   numeric := 0;
  v_disc      numeric := 0;
  v_subtotal  numeric;
  v_total     numeric;
  v_manual    numeric := 0;
  v_new_bd    jsonb;
  v_new_total int;
  v_apply     boolean := false;
begin
  -- 1) Calcular la version "sin convenio" en variables locales. Si algo falla
  --    aqui, NEW no se toca (fail-open, igual que el guard original).
  begin
    if NEW.restaurant_id = c_pangoa
       and coalesce(NEW.pricing_breakdown::text, '') ~* 'convenio'
       and (TG_OP = 'INSERT'
            or coalesce(OLD.pricing_breakdown::text, '') !~* 'convenio')
    then
      v_bd    := NEW.pricing_breakdown;
      v_lines := coalesce(v_bd->'discountLines', '[]'::jsonb);

      select coalesce(jsonb_agg(dl order by ord), '[]'::jsonb),
             coalesce(sum(coalesce((dl->>'amount')::numeric, 0)), 0)
        into v_kept, v_disc
        from jsonb_array_elements(v_lines) with ordinality as t(dl, ord)
       where coalesce(dl->>'label', '') !~* 'convenio';

      select coalesce(sum(coalesce((dl->>'amount')::numeric, 0)), 0)
        into v_removed
        from jsonb_array_elements(v_lines) dl
       where coalesce(dl->>'label', '') ~* 'convenio';

      v_subtotal := coalesce((v_bd->>'subtotal')::numeric, NEW.subtotal, 0);

      if jsonb_array_length(v_kept) = 0
         or coalesce((v_bd - 'discountLines')::text, '') ~* 'convenio' then
        -- Sin descuentos automaticos restantes (o forma desconocida):
        -- queda como una orden normal sin breakdown.
        v_new_bd := null;
        v_disc   := 0;
      else
        v_total  := greatest(0, v_subtotal - v_disc);
        v_new_bd := v_bd || jsonb_build_object('discountLines', v_kept,
                                               'totalDiscount', v_disc,
                                               'total', v_total);
        if v_bd ? 'suggestedTip' then
          -- Regla general: propina sugerida sobre el total con descuento.
          v_new_bd := v_new_bd || jsonb_build_object('suggestedTip', round(v_total * 0.10));
        end if;
        if v_bd ? 'finalTotal' then
          v_new_bd := v_new_bd || jsonb_build_object(
            'finalTotal', v_total + coalesce((v_new_bd->>'suggestedTip')::numeric, 0));
        end if;
      end if;

      -- orders.total sin el convenio: subtotal - descuento manual - otros automaticos.
      if NEW.discount_type = 'porcentaje' then
        v_manual := round(coalesce(NEW.subtotal, 0) * coalesce(NEW.discount_value, 0) / 100.0);
      elsif NEW.discount_type = 'monto' then
        v_manual := coalesce(NEW.discount_value, 0);
      end if;
      v_new_total := greatest(0, coalesce(NEW.subtotal, 0) - v_manual - v_disc)::int;
      v_apply := true;
    end if;
  exception when others then
    v_apply := false;
  end;

  if not v_apply then
    return NEW;
  end if;

  -- 2) Aplicar (asignaciones simples, no pueden fallar).
  NEW.pricing_breakdown := v_new_bd;
  NEW.total := v_new_total;

  -- 3) Dejar rastro para administracion. Nunca bloquea el POS.
  begin
    insert into public.order_logs (restaurant_id, order_id, action, details)
    values (c_pangoa, NEW.id, 'convenio_descontinuado_ignorado',
            jsonb_build_object(
              'motivo', 'Descuento Convenio descontinuado (01-sep-2026): se ignoro sin bloquear la orden',
              'convenio_amount', v_removed,
              'subtotal', NEW.subtotal,
              'total', NEW.total,
              'discount_type', NEW.discount_type,
              'discount_value', NEW.discount_value,
              'op', TG_OP));
  exception when others then
    null;
  end;

  return NEW;
end
$function$;

comment on function public.pangoa_guard_convenio_descontinuado() is
  'Pangoa: ignora (no bloquea) el Descuento Convenio descontinuado. Antes lanzaba excepcion y eso impedia imprimir la precuenta.';
