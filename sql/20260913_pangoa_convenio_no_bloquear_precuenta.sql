-- Pangoa: precuenta no se imprimia al elegir el "Descuento Convenio"
-- (descontinuado el 01-sep-2026).
--
-- El guard trg_pangoa_guard_convenio lanzaba excepcion en CUALQUIER update de
-- la orden que trajera "convenio" en pricing_breakdown. El POS pide la
-- precuenta con ese mismo UPDATE (notes = 'PRECUENTA_REQUEST'), asi que la
-- nota nunca se escribia y no se encolaba el print_job.
--
-- Comportamiento nuevo del guard (misma regla de negocio: el Convenio NO se
-- aplica), segun el tipo de UPDATE:
--
--   a) Pedido de precuenta (notes = 'PRECUENTA_REQUEST') con Convenio:
--      se quitan las lineas Convenio del breakdown, se recalculan
--      totalDiscount/total/finalTotal/suggestedTip y orders.total, se deja
--      rastro en order_logs ('convenio_descontinuado_ignorado') y la fila
--      pasa -> la precuenta se imprime SIN el Convenio.
--
--   b) Cualquier otro update que intente aplicar el Convenio (aplicar el
--      descuento, cerrar una mesa que nunca paso por a): sigue rechazado con
--      la misma excepcion y un hint mas claro. El POS muestra el aviso de
--      inmediato y el Convenio nunca se persiste.
--
--   c) Cierre (status -> 'cerrada') de una orden que ya paso por a): no se
--      bloquea (el pago ya esta insertado; bloquear generaria pagos
--      duplicados). Si el update trae Convenio en el breakdown se quita igual
--      que en a). Si el total cobrado es mas bajo de lo que explican el
--      descuento manual + los descuentos automaticos, el POS cobro igual el
--      monto con Convenio: ese descuento queda REGISTRADO como manual 'monto'
--      y se deja rastro en order_logs ('convenio_cobrado_descontinuado').
--
--   Fail-open: si algo falla dentro del guard, la fila pasa sin cambios.
--
-- Respaldo de la definicion original: public._bak_pangoa_guard_convenio_20260913
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
  c_pangoa      constant uuid := '816da88d-56a8-4d0d-81d3-48b1815515ea';
  v_new_conv    boolean := false;  -- el update trae Convenio y la orden no lo tenia
  v_precuenta   boolean := false;  -- el update pide precuenta
  v_closing     boolean := false;  -- el update cierra la mesa
  v_marked      boolean := false;  -- la orden ya paso por un Convenio ignorado
  v_block       boolean := false;
  v_strip       boolean := false;
  v_record      boolean := false;
  v_bd          jsonb;
  v_lines       jsonb;
  v_kept        jsonb;
  v_removed     numeric := 0;
  v_disc        numeric := 0;
  v_subtotal    numeric;
  v_total       numeric;
  v_manual      numeric := 0;
  v_new_bd      jsonb;
  v_new_total   int;
  v_bd_disc     numeric := 0;
  v_expected    int;
  v_hidden      int := 0;
  v_reg_value   int;
begin
  if NEW.restaurant_id is distinct from c_pangoa then
    return NEW;
  end if;

  -- 1) Decidir y calcular, todo en variables locales (fail-open).
  begin
    v_new_conv := coalesce(NEW.pricing_breakdown::text, '') ~* 'convenio'
                  and (TG_OP = 'INSERT'
                       or coalesce(OLD.pricing_breakdown::text, '') !~* 'convenio');
    v_precuenta := coalesce(TG_OP = 'UPDATE'
                   and NEW.notes = 'PRECUENTA_REQUEST'
                   and OLD.notes is distinct from 'PRECUENTA_REQUEST', false);
    v_closing := coalesce(TG_OP = 'UPDATE'
                 and NEW.status = 'cerrada' and OLD.status is distinct from 'cerrada', false);
    if v_closing then
      v_marked := exists (select 1 from public.order_logs l
                           where l.order_id = NEW.id
                             and l.action = 'convenio_descontinuado_ignorado');
    end if;

    if v_new_conv then
      if v_precuenta or (v_closing and v_marked) then
        v_strip := true;
      else
        v_block := true;
      end if;
    end if;

    if NEW.discount_type = 'porcentaje' then
      v_manual := round(coalesce(NEW.subtotal, 0) * coalesce(NEW.discount_value, 0) / 100.0);
    elsif NEW.discount_type = 'monto' then
      v_manual := coalesce(NEW.discount_value, 0);
    end if;

    if v_strip then
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
      v_new_total := greatest(0, coalesce(NEW.subtotal, 0) - v_manual - v_disc)::int;
    end if;

    if v_closing and v_marked and not v_block then
      v_bd_disc  := coalesce(((case when v_strip then v_new_bd else NEW.pricing_breakdown end)->>'totalDiscount')::numeric, 0);
      v_expected := greatest(0, coalesce(NEW.subtotal, 0) - v_manual - v_bd_disc
                                - coalesce(NEW.auto_discount_value, 0))::int;
      v_hidden   := v_expected - coalesce(NEW.total, 0);
      if v_hidden > 1 then
        v_record    := true;
        v_reg_value := greatest(0, coalesce(NEW.subtotal, 0) - coalesce(NEW.total, 0)
                                   - v_bd_disc - coalesce(NEW.auto_discount_value, 0))::int;
      end if;
    end if;
  exception when others then
    return NEW;
  end;

  if v_block then
    raise exception 'El Descuento Convenio fue descontinuado (01-sep-2026). Ya no se aplica en Pangoa.'
      using hint = 'Quite el Descuento Convenio y use otro descuento. Si administracion decide reactivarlo, hay que quitar el trigger trg_pangoa_guard_convenio.';
  end if;

  if not v_strip and not v_record then
    return NEW;
  end if;

  -- 2) Aplicar (asignaciones simples, no pueden fallar).
  if v_strip then
    NEW.pricing_breakdown := v_new_bd;
    if not v_closing then
      NEW.total := v_new_total;   -- al cerrar, el total cobrado es el que vale
    end if;
  end if;
  if v_record then
    NEW.discount_type  := 'monto';
    NEW.discount_value := v_reg_value;
  end if;

  -- 3) Dejar rastro para administracion. Nunca bloquea el POS.
  begin
    if v_strip then
      insert into public.order_logs (restaurant_id, order_id, action, details)
      values (c_pangoa, NEW.id, 'convenio_descontinuado_ignorado',
              jsonb_build_object(
                'motivo', 'Descuento Convenio descontinuado (01-sep-2026): se ignoro; la precuenta/cierre sigue sin el',
                'convenio_amount', v_removed,
                'subtotal', NEW.subtotal,
                'total', NEW.total,
                'discount_type', NEW.discount_type,
                'discount_value', NEW.discount_value,
                'en_cierre', v_closing,
                'op', TG_OP));
    end if;
    if v_record then
      insert into public.order_logs (restaurant_id, order_id, action, details)
      values (c_pangoa, NEW.id, 'convenio_cobrado_descontinuado',
              jsonb_build_object(
                'motivo', 'La mesa se cerro cobrando un total con Convenio (descontinuado). El descuento quedo registrado como manual monto para que no quede oculto en reportes.',
                'monto_no_explicado', v_hidden,
                'subtotal', NEW.subtotal,
                'total', NEW.total,
                'discount_type_original', OLD.discount_type,
                'discount_value_original', OLD.discount_value,
                'discount_value_registrado', NEW.discount_value,
                'op', TG_OP));
    end if;
  exception when others then
    null;
  end;

  return NEW;
end
$function$;

comment on function public.pangoa_guard_convenio_descontinuado() is
  'Pangoa: Convenio descontinuado. Bloquea aplicarlo, pero deja imprimir la precuenta (sin Convenio) y registra si igual se cobro al cerrar.';

-- Correccion de datos: la orden 3425 (13-sep-2026) se cerro cobrando el
-- Convenio (subtotal 38.600, total 27.880, sin descuento registrado) durante
-- la ventana en que la version intermedia del guard no lo bloqueaba.
-- Se registra el descuento como manual 'monto' para que no quede oculto.
update public.orders o
   set discount_type = 'monto', discount_value = o.subtotal - o.total
 where o.restaurant_id = '816da88d-56a8-4d0d-81d3-48b1815515ea'
   and o.order_number = 3425 and o.status = 'cerrada'
   and o.discount_type = 'none' and o.total < o.subtotal;

insert into public.order_logs (restaurant_id, order_id, action, details)
select o.restaurant_id, o.id, 'convenio_cobrado_descontinuado',
       jsonb_build_object('motivo', 'Correccion manual 13-sep-2026: la mesa se cerro cobrando el Convenio descontinuado; se registro como descuento monto.',
                          'subtotal', o.subtotal, 'total', o.total, 'discount_value_registrado', o.discount_value)
  from public.orders o
 where o.restaurant_id = '816da88d-56a8-4d0d-81d3-48b1815515ea'
   and o.order_number = 3425 and o.discount_type = 'monto'
   and not exists (select 1 from public.order_logs l where l.order_id = o.id and l.action = 'convenio_cobrado_descontinuado');
