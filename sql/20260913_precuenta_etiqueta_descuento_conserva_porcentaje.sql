-- Precuenta/cuenta: conservar el porcentaje en la etiqueta del descuento
-- cuando la etiqueta viene de una sola linea del pricing_breakdown y no hay
-- descuento manual encima (ej. Pangoa "Descuento Convenio 40% cocina": el 40%
-- aplica solo a cocina, asi que el monto no es 40% del subtotal y el
-- saneador de enqueue_print_job borraba el "40%").
--
-- El saneador (migracion precuenta_include_manual_discount, 10-jun-2026) se
-- mantiene para los casos en que la etiqueta dejaria de describir el monto
-- impreso: descuento manual sumado encima, o varias lineas de descuento
-- combinadas en un solo monto.
--
-- Se edita la funcion por reemplazo de texto (mismo patron que la migracion
-- pangoa_convenio_tip_pre_descuento) verificando que cada patron aparezca
-- exactamente una vez.
--
-- Aplicada en produccion como migracion
-- `precuenta_etiqueta_descuento_conserva_porcentaje`.

do $do$
declare
  v_def text; v_new text; n int; pat text;
  p_if   constant text := 'if v_subtotal > 0' || chr(10) || '       and v_discount_label ~ ';
  p_decl constant text := '  v_item_discount numeric;' || chr(10) || 'begin';
  p_lbl1 constant text := $q$v_discount_label := coalesce(v_bd->'discountLines'->0->>'label', 'Descuento') || ':';$q$;
  p_lbl2 constant text := $q$v_discount_label := coalesce(v_bd->'extras'->'discountLines'->0->>'label', 'Descuento') || ':';$q$;
begin
  select pg_get_functiondef(p.oid) into v_def
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname = 'enqueue_print_job';
  if v_def is null then raise exception 'public.enqueue_print_job no existe'; end if;

  foreach pat in array array[p_if, p_decl, p_lbl1, p_lbl2] loop
    n := (length(v_def) - length(replace(v_def, pat, ''))) / length(pat);
    if n <> 1 then raise exception 'patron "%" aparece % veces (se esperaba 1)', left(pat, 40), n; end if;
  end loop;

  v_new := replace(v_def, p_decl, '  v_item_discount numeric;' || chr(10) || '  v_label_lines int := 0;' || chr(10) || 'begin');
  v_new := replace(v_new, p_lbl1, p_lbl1 || chr(10) || $q$      v_label_lines := jsonb_array_length(coalesce(v_bd->'discountLines', '[]'::jsonb));$q$);
  v_new := replace(v_new, p_lbl2, p_lbl2 || chr(10) || $q$      v_label_lines := jsonb_array_length(coalesce(v_bd->'extras'->'discountLines', '[]'::jsonb));$q$);
  v_new := replace(v_new, p_if,
    'if v_subtotal > 0' || chr(10) ||
    '       and (v_manual > 0 or v_label_lines > 1)' || chr(10) ||
    '       and v_discount_label ~ ');
  execute v_new;
end
$do$;
