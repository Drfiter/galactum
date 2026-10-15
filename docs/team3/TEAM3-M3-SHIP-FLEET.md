# M3 Representación y selección de naves

Rama de trabajo: `feature/team3-m3-ship-fleet`.
Baseline: M2, protocolo `team3-m2.0`. El contrato y el SSS no se modifican.

## Alcance implementado

Esta tarea ofrece datos tipados de naves visibles y selección independiente de
la presentación para las tareas de Minería y Combate. Mantiene la vista diagnóstica
existente y la entrada por mouse/touch. No establece la presentación final del juego.

`ShipRepresentation` es una copia de los datos recibidos, con `entity_id`,
`ship_id`, `player_id`, `system_id`, `display_name`, `position` y `state`.
Los identificadores no se intercambian ni se derivan de nombres de Nodes.
Los campos de identidad no recibidos permanecen vacíos; un `player_id` vacío
significa propietario desconocido. `is_owned_by(player_id)` requiere un ID
autenticado no vacío. Este chequeo local no sustituye la autorización del SSS.

La posición del modelo es la recibida del servidor, representada mediante Vector2
sin introducir otra unidad o regla de red. `to_entity()` devuelve una copia profunda
compatible con `TravelProjection`; conserva el bloque `travel`, incluido su valor
null o su ausencia. Cambiar el modelo o esa copia no altera `WorldState`.

## Interfaz para otras tareas

```gdscript
var actor: ShipRepresentation = world_state.get_ship(actor_entity_id)
if actor == null:
    return # No es una nave visible en la réplica actual.
var ship_id: String = actor.ship_id
var owner_id: String = actor.player_id
var authoritative_position: Vector2 = actor.position

var own_ship: ShipRepresentation = world_state.get_ship_for_player(player_id)
var selected_ship: ShipRepresentation = selection.get_selected_ship()
```

`WorldState.get_ship(entity_id)` devuelve null para una entidad ausente o de otro
tipo. `get_ship_for_player(player_id)` conserva la búsqueda M2 de una nave por
jugador. No se incorpora una regla para controlar varias naves propias.
Las consultas anteriores que devuelven Dictionary siguen disponibles.

`ShipSelectionState.new(world_state)` se compone con la réplica, sin Autoload.
Ofrece `select_entity(entity_id)`, `clear()`, `selected_entity_id`,
`get_selected_ship()` y la señal `changed`. Preserva selección genérica para
asteroides/xenoformas, aunque `get_selected_ship()` devuelve null para esos tipos.
Emite cambios cuando hay selección, actualizaciones del mundo con una selección
activa o invalidación. `removed`, un snapshot que excluye la entidad y `clear()`
invalidan el ID seleccionado. Una salida del AOI no significa destrucción.

El consumidor debe consultar nuevamente el modelo después de `WorldState.changed`
o `selection.changed`; una copia anterior no es un estado vivo. Minería puede
identificar actor y asteroide; Combate puede identificar actor y objetivo mediante
IDs. Esta rama no envía mensajes de acciones ni decide rango, permisos, extracción,
daño o resultados. Las verificaciones autoritativas pertenecen a sus tareas del SSS.

`WorldDebugView.set_selection_state(selection)` permite usar la misma selección
que consumen los otros componentes. La señal de input `entity_selected` permanece
disponible por compatibilidad; los consumidores que necesiten invalidaciones o
actualizaciones deben observar `selection.changed`.

## Garantías de M2

- `start_travel` sigue enviando únicamente destination y el sobre acordado.
- Una sola solicitud permanece pendiente; perder selección no la confirma/rechaza.
- Un `TRAVELING` de la nave propia confirma la solicitud, incluso si la selección
  fue invalidada antes. Una nave ajena no puede confirmarla.
- Se conserva ANCHORED/TRAVELING, ETA, timestamps y llegada con travel null.
- La proyección visual no escribe posición en WorldState ni en el modelo.
- Reconexión/desconexión/resume descartan selección y destino transitorios.
- Snapshot durante viaje reconstruye trayectoria y ETA.

`TravelIntentState.selected_own_ship_id` se renombró a `selected_own_entity_id`:
su valor siempre ha sido un entity_id. Otras ramas deben actualizar cualquier
referencia al nombre anterior. El modelo no incorpora lógica de movimiento.
El `ShipState` histórico del SSS permanece sin cambios y no es la nueva interfaz.

## Decisiones pendientes

No se implementan flotas funcionales: el contrato sólo enumera kind fleet y no
define fleet_id, composición, ownership o movimiento. No se asigna fleet_id a una
nave por inferencia. Los marcadores genéricos fleet existentes siguen disponibles.

No se requieren estadísticas de Equipo 2 para estas consultas, por lo que no se
crea provider/mock adicional. Stats, múltiples naves controlables y contrato de
flotas necesitan fuentes y acuerdo antes de incorporarse. Las decisiones de
`OPEN_DECISIONS.md` y la deuda de la introducción del contrato permanecen abiertas.

## Verificación

Ejecutado el 2026-10-14 con Godot 4.6.2 stable en Windows, sobre el árbol de trabajo
sin commit de esta rama. Baseline HEAD: c975f37. Cada prueba siguiente terminó
con código 0 y su marcador OK:

| Proyecto | Prueba | Resultado |
| --- | --- | --- |
| Cliente | m1_client_world_state_test | OK |
| Cliente | m1_sss_connection_sequence_test | OK |
| Cliente | m2_sss_connection_test | OK |
| Cliente | m2_travel_intent_test | OK |
| Cliente | m2_travel_projection_test | OK |
| Cliente | m2_world_debug_view_test | OK |
| Cliente | m3_ship_representation_test | OK |
| Cliente | m3_ship_selection_test | OK |
| Cliente + SSS | m3_ship_scene_test | OK |
| SSS | travel_math_test | OK |
| SSS | travel_start_test | OK |
| SSS | travel_snapshot_test | OK |
| SSS | travel_delta_test | OK |
| SSS | travel_tick_test | OK |
| SSS | travel_aoi_test | OK |

Las pruebas nuevas de representación y selección fallaron antes de implementar
las interfaces. La regresión de confirmación tras perder selección falló antes
de su corrección y pasó después. Se verificaron copias anidadas, ownership
desconocido, llegada, snapshots, AOI y selección por mouse/touch simulados.

Para ejecutar desde la raíz, godot representa el ejecutable local de Godot 4.6.2:

```powershell
godot --headless --editor --path . --import
godot --headless --editor --path server/sss --import
godot --headless --path . --script res://tests/m3_ship_representation_test.gd
godot --headless --path . --script res://tests/m3_ship_selection_test.gd
# En una terminal separada, servidor nuevo para la demo:
godot --headless --path server/sss -- --port=19200
# En otra terminal, después de SSS_READY:
godot --headless --max-fps 60 --path . --script res://tests/m3_ship_scene_test.gd -- --port=19200
```

Las demás pruebas se ejecutan según `../TESTING.md`. Los smoke tests históricos
M0/M1 no son evidencia E2E del protocolo M2. La demo nueva usa la escena principal,
SSS real, selección táctil simulada, cancelación, inicio, reconexión y llegada a una
celda adyacente. Debe partir de un SSS nuevo con su seed predeterminado.

La importación del editor informó herramientas Android build-tools no disponibles.
No se generó APK ni se validó dispositivo físico, layout visual o background/resume
del sistema operativo Android. Reconexión y reconstrucción sí se verificaron en PC.

## Demo manual e integración

1. Iniciar SSS y cliente según `../DEVELOPMENT.md`.
2. Seleccionar la nave propia por click/tap; elegir destino y cancelar.
3. Elegir otro destino y confirmar. Comprobar que no permite otra solicitud pendiente.
4. Reconectar durante viaje: selección/destino se limpian y la ruta/ETA se reconstruyen.
5. Verificar llegada ANCHORED y seleccionar una nave ajena; no debe habilitar viaje.
6. Repetir en dispositivo Android con varias resoluciones y background/resume.

Para integrar después a integration/team3-m3, revisar especialmente cambios
concurrentes en app/main.gd, WorldState, WorldDebugView y TravelIntentState. Conservar
una selección compuesta con la misma réplica, el renombre del ID y la semántica M2.
Minería/Combate deben consumir los modelos/IDs y no acceder a controles o NodePaths.
Repetir las 15 pruebas en la rama de integración y validar Android antes de entrega.
No se realizaron commit, push, merge ni PR en esta tarea.
