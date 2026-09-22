# Análisis de venta de productos — Almíbar

**Empresa:** Inversiones Alma SpA · **Local:** Almíbar (bar, Curicó) · con línea importada de Pangoa (Talca)
**Fecha:** 22-09-2026

## 1. Alcance y fuentes

| Fuente | Qué aporta |
| --- | --- |
| `carta-almibar-final-descripciones.md` (Drive) | Carta completa: 41 ítems, precios vigentes (clásicos) y sugeridos (línea nueva) |
| `fichas-tecnicas-almibar.md` (Drive) | Costeo receta por receta de **20 platos** de la línea nueva (peruana) |
| `Club de Amigos - Almíbar` (Drive, planilla) | Registro de socios: visitas totales, última visita, premios canjeados, tier VIP |
| `index.html` (este repo) | ERP: campos de finanzas/operaciones por local, hoy sin datos cargados |

**Lo que NO existe y bloquea el análisis completo:**

1. **Unidades vendidas por producto.** No hay ningún export de Fudo en Drive ni en correo. Sin unidades no hay análisis de mix (estrella / vaca / perro / rompecabezas), que es el núcleo de un análisis de venta de productos. Los únicos tres datos de volumen del universo son menciones sueltas de Pangoa dentro de las fichas: Lomo Saltado 512u, Fetuccini Huancaína 250u, Crema Volteada 280u.
2. **Costeo de lo que se vende hoy.** Las fichas costean los 20 platos **nuevos**. Los 12 clásicos marcados `AL` —los que generan la venta actual, incluida "nuestra #1" La Suprema— no tienen ficha. Se analiza aquí con estimaciones explícitas (§5).
3. **Costeo de barra.** Almíbar es un bar y no hay una sola ficha de trago. En un bar la barra suele ser la mitad o más de la venta; hoy es un punto ciego total.

---

## 2. Hallazgos

### H1 · El food cost promedio está mal etiquetado, y el número correcto no cambia la conclusión

Las fichas reportan "food cost promedio **ponderado** ~18%". No es ponderado: no hay unidades con las que ponderar. Los valores reales sobre los 20 platos costeados:

- **17,4%** promedio simple por plato
- **18,9%** agregado (suma de costos / suma de precios, equivale a vender 1u de cada uno)

Ambos quedan muy por debajo del objetivo de 30%. La lectura de las fichas ("hay holgura de precio") es solo una de dos lecturas posibles; la otra es que **el precio ya está alto para la plaza de Curicó y la holgura conviene gastarla en gramaje y calidad percibida**, no en subir precio. Sin unidades vendidas no se puede saber cuál de las dos aplica: es exactamente la decisión que el dato faltante bloquea.

### H2 · El food cost % está ordenando mal las prioridades comerciales

Las fichas marcan como "más rentables" los platos de menor FC%. Por margen absoluto el orden se invierte:

| Plato | FC% | Margen unitario | Lectura de las fichas | Realidad |
| --- | --- | --- | --- | --- |
| Tabla Pacífico | 24,9% | **$22.451** | casi el peor FC | **el mejor plato de la carta** |
| Empanada Lomo Saltado | 18,7% | **$3.986** | FC sano | **el que menos aporta** |
| Yuquitas con Ocopa | 13,7% | $5.953 | "el piqueo más rentable" | 4º de 5 piqueos por margen |
| Crema Volteada | 8,8% | $5.379 | "mejor food cost de la carta" | aporta 1/4 de una Tabla Pacífico |

Vender una Tabla Pacífico equivale a **5,6 empanadas** de margen. Empujar por FC% lleva al equipo a vender los ítems que menos plata dejan.

### H3 · Los fondos tienen precio plano: se anuló la capacidad de dirigir el mix

Seis de los siete fondos están entre $16.500 y $16.900:

| Fondo | Costo | Precio | FC% | Margen | Tiempo cocina |
| --- | --- | --- | --- | --- | --- |
| Lomo Saltado | $2.590 | $16.500 | 15,7% | $13.910 | 12 min |
| Fetuccini Huancaína | $2.977 | $16.900 | 17,6% | $13.923 | 14 min |
| Salmón a la Maracuyá | $2.986 | $16.900 | 17,7% | $13.914 | 12 min |
| Risotto al Pesto | $3.395 | $16.900 | 20,1% | $13.505 | **18 min** |
| Lomo Mar y Tierra | $3.798 | $16.900 | 22,5% | $13.102 | 13 min |
| Filete a lo Macho | $4.269 | $16.900 | 25,3% | $12.631 | 14 min |
| Anticuchera Almíbar | $5.170 | $18.900 | 27,4% | $13.730 | 12 min + mesa |

El costo varía $2.580 entre extremos y el precio solo $2.400: el margen queda plano en una banda de $1.292 (10%).

Eso es defendible en margen, pero tiene dos costos ocultos:
- **El plato más lento no paga su lentitud.** El Risotto ocupa 18 min de línea —50% más que el Lomo Saltado— y deja $405 menos de margen. En el peak, cada Risotto desplaza producción; a precio plano, el cliente no tiene ninguna señal para elegir otra cosa.
- **No hay palanca de mix.** Con todo a $16.900, la única forma de mover al cliente hacia el plato más barato de producir (Lomo Saltado, FC 15,7%) es la recomendación del garzón. Un escalón de $500–$1.000 haría el trabajo solo.

### H4 · El plato más lento es también el cuello de botella de la venta

Lomo Saltado, Mar y Tierra y Fetuccini comparten un solo wok, con techo declarado de **~12 fondos/hora** en el peak 20–22h. Eso pone un techo duro al aporte de toda la línea:

- **$157.000 – $167.000 de margen por hora** de peak
- **~$314.000 – $334.000** en las dos horas de peak

Los piqueos, en cambio, salen de freidora y van pre-congelados: cero armado en servicio y sin techo comparable. **El crecimiento de volumen tiene que venir de piqueos y barra fría, no de fondos.** La línea de fondos es de ticket, no de volumen, y conviene tratarla así (pocas referencias, bien ejecutadas).

### H5 · Los clásicos actuales probablemente rinden más que la línea nueva — y nadie los ha costeado

Costeo **estimado** de los clásicos con los precios de insumo reales de las fichas (papas $1.593/kg, pollo $3.200/kg, crema $4.000/lt, salmón $11.364/kg, queso crema $8.816/kg) y supuestos de mercado para el resto:

| Clásico (precio vigente) | Costo est. | FC est. | Margen est. |
| --- | --- | --- | --- |
| La Peruana · $20.800 | $2.063 | 9,9% | **$18.737** |
| La Mortal · $18.800 | $2.911 | 15,5% | **$15.889** |
| La Suprema · $16.700 *(la #1)* | $1.908 | 11,4% | **$14.792** |
| Pizza Mechona · $16.600 | $3.615 | 21,8% | $12.985 |
| Hamburguesa Gringa · $12.500 | $2.815 | 22,5% | $9.685 |
| Pollo Crispy Roll · $8.990 | $1.496 | 16,6% | $7.494 |
| Papas Fritas · $7.400 | $708 | 9,6% | $6.692 |
| Salmón Roll · $8.990 | $2.190 | 24,4% | $6.800 |
| Cheese Burger · $9.100 | $2.780 | **30,5%** | $6.320 |

> Estimaciones propias, no fichas. Los gramajes son supuestos; sirven para ordenar prioridades, no para fijar precio. Hay que costear estos nueve platos con receta real antes de decidir nada.

Con esos supuestos, **La Peruana ($18.737) y La Mortal ($15.889) superan al mejor fondo nuevo ($13.923)** y solo la Tabla Pacífico ($22.451) las pasa. Implicancia directa: la línea Pangoa entra a la carta **por debajo** de los clásicos en margen y **por encima** en tiempo de cocina. Si desplaza ventas de La Peruana o La Suprema, la carta nueva puede subir el ticket promedio y **bajar** el margen total. Ese es el riesgo principal del lanzamiento y hoy no está medido.

### H6 · Tres anomalías de precio concretas, accionables esta semana

1. **Salmón Roll y Pollo Crispy Roll al mismo precio ($8.990).** El insumo principal cuesta 3,6x más ($11.364/kg vs $3.200/kg). Margen estimado $6.800 vs $7.494: **9% menos por unidad vendida**, y es el segundo roll más pedido. Corresponde diferenciar precio (~$10.500) o bajar el gramaje de salmón.
2. **Promo 20 Piezas a $15.900 = $795/pieza.** Un roll individual a $8.990 sale entre $899 y $1.124 la pieza según formato: la promo descuenta entre **12% y 29%**. Es el ítem con más riesgo de canibalizar al roll #1 de la casa y no hay dato de cuánto se vende de cada uno.
3. **Cheese Burger a $9.100 con doble carne: FC estimado 30,5%** — el único ítem de la carta que toca el techo del 30%. Al lado, la Hamburguesa Gringa cobra $12.500 por **un** medallón. La estructura está invertida.

### H7 · El Club de Amigos no puede medir venta por producto

La planilla de socios (1.500+ registros) guarda `Visitas Totales`, `Última Visita` y `Premios Canjeados`, pero **no guarda qué consumió el socio**. No hay forma de responder "¿qué productos compran los socios VIP?" ni de medir si el club mueve la venta de los platos de mayor margen. Tampoco hay costo asociado a los premios canjeados, así que el programa no tiene medición de rentabilidad.

Además, la calidad del registro afectaría cualquier cruce futuro:
- filas `(auto-creado)` sin nombre, RUT ni contacto (más de 15 en la primera página);
- una fila de prueba `NOEXISTE-TEST` con **99 visitas** que contamina cualquier promedio;
- socios duplicados con dos ID de miembro (Agustina Fuenzalida, Alexis Meza, Astrid Medina);
- la mayoría de los socios con `Visitas Totales = 0`, es decir captados y nunca activados;
- formatos de fecha mezclados en la misma columna (`2026-05-09T21:12:59.278Z`, `23/3/2026 20:29:57`, `30-03-2025, 1:00`).

---

## 3. Qué hacer, en orden

| # | Acción | Por qué | Esfuerzo |
| --- | --- | --- | --- |
| 1 | **Exportar de Fudo el reporte de productos** (unidades + venta $ por producto, últimos 90 días, ambos locales) | Sin esto no hay análisis de mix ni forma de validar nada de lo anterior | 10 min |
| 2 | **Costear los 12 clásicos `AL`** con receta y gramaje real | Es la venta de hoy; H5 sugiere que son el motor de margen y están sin medir | 1 día de cocina |
| 3 | **Costear la barra** (al menos los 15 tragos más vendidos) | Punto ciego más grande del negocio; sin esto los bundles After no se pueden validar | 1 día |
| 4 | Diferenciar precio del **Salmón Roll** y revisar **Cheese Burger** | Fugas de margen identificadas, corrección inmediata | 1 hora |
| 5 | Abrir **escalones de precio en fondos** ($16.500 / $17.500 / $18.900 según costo y tiempo) | Recupera la palanca de mix y hace que el Risotto pague su lentitud | 1 hora |
| 6 | Reordenar el **discurso de venta por margen absoluto**, no por FC% | Tabla Pacífico y Ronda de Ceviches son los dos ítems a empujar; hoy el foco está en los piqueos baratos | Brief de equipo |
| 7 | Agregar **ID de socio al ticket de Fudo** | Habilita medir venta por producto por socio y recién ahí evaluar el club | Config POS |
| 8 | Limpiar la planilla del club (borrar `NOEXISTE-TEST`, deduplicar, normalizar fechas) | Cualquier cruce futuro hereda estos errores | 2 horas |
| 9 | Corregir las recetas de Pangoa en `recipes`/`recipe_items` | Ya marcado como pendiente crítico en las fichas: hoy ningún reporte de margen o merma es confiable | — |

---

## 4. Anexo · Los 20 platos costeados, por margen unitario

| # | Plato | Costo | Precio | FC% | Margen | Sección |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | Tabla Pacífico | $7.449 | $29.900 | 24,9% | $22.451 | Tablas |
| 2 | Ronda de Ceviches | $3.048 | $19.900 | 15,3% | $16.852 | Ceviches |
| 3 | Tiradito Almíbar | $1.827 | $16.900 | 10,8% | $15.073 | Ceviches |
| 4 | Fetuccini Huancaína | $2.977 | $16.900 | 17,6% | $13.923 | Fondos |
| 5 | Salmón a la Maracuyá | $2.986 | $16.900 | 17,7% | $13.914 | Fondos |
| 6 | Lomo Saltado | $2.590 | $16.500 | 15,7% | $13.910 | Fondos |
| 7 | Anticuchera Almíbar | $5.170 | $18.900 | 27,4% | $13.730 | Fondos |
| 8 | Risotto al Pesto | $3.395 | $16.900 | 20,1% | $13.505 | Fondos |
| 9 | Lomo Mar y Tierra | $3.798 | $16.900 | 22,5% | $13.102 | Fondos |
| 10 | Ceviche Mixto Almíbar | $3.159 | $15.900 | 19,9% | $12.741 | Ceviches |
| 11 | Filete a lo Macho | $4.269 | $16.900 | 25,3% | $12.631 | Fondos |
| 12 | Alitas a lo Bróster | $1.963 | $9.900 | 19,8% | $7.937 | Piqueos |
| 13 | Causa Bomba | $1.303 | $8.900 | 14,6% | $7.597 | Piqueos |
| 14 | Croquetas Ají de Gallina | $1.282 | $7.900 | 16,2% | $6.618 | Piqueos |
| 15 | Yuquitas con Ocopa | $947 | $6.900 | 13,7% | $5.953 | Piqueos |
| 16 | Picarones | $851 | $6.500 | 13,1% | $5.649 | Postres |
| 17 | Crema Volteada | $521 | $5.900 | 8,8% | $5.379 | Postres |
| 18 | Leche de Tigre | $851 | $5.900 | 14,4% | $5.049 | Ceviches |
| 19 | Suspiro Limeño | $677 | $5.500 | 12,3% | $4.823 | Postres |
| 20 | Empanada Lomo Saltado | $914 | $4.900 | 18,7% | $3.986 | Piqueos |

**Único dato de volumen disponible** (menciones de Pangoa en las fichas):

| Producto | Unidades | Margen unitario | Aporte |
| --- | --- | --- | --- |
| Lomo Saltado | 512u | $13.910 | $7.121.920 |
| Fetuccini Huancaína | 250u | $13.923 | $3.480.750 |
| Crema Volteada | 280u | $5.379 | $1.506.120 |
| | | | **$12.108.790** |

Sin período de referencia asociado, estas cifras no son proyectables. Se incluyen solo para mostrar el orden de magnitud que tendría el análisis completo una vez cargado el export de Fudo.
