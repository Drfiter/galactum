# TEAM3-M3 — Diseño propuesto de Asteroides y Minería

## Revisión posterior de convivencia con Combat

El cierre anterior registra minería sobre 2899abb. La solución combinada con
Combat a18c195 y la cancelación minera elegida por el usuario se implementaron y
probaron en una copia independiente. El usuario autorizó posteriormente commit,
push y merge hacia integration/team3-m3, trasladando la solución validada y
conservando un respaldo de los cambios locales previos.
Ver [TEAM3-M3-MINING-COMBAT-REVIEW.md](TEAM3-M3-MINING-COMBAT-REVIEW.md) para
ubicación, resultados, regla aprobada y siguiente acción. No confundir ambas bases.


## Estado, fuentes y clasificación

ETAPA 1 entregada. El usuario autorizó continuar con ETAPA 2 sobre este diseño.
ETAPA 2 implementada: modelo y sincronización. El usuario autorizó continuar
con ETAPA 3, implementada: ciclo autoritativo SSS y extensión de protocolo.
El usuario autorizó continuar con ETAPA 4, implementada: cliente y UX mínima.
ETAPA 5 completada: auditoría, regresiones y documentación de cierre.
Las reglas de etapas posteriores conservan su clasificación provisional y
requieren autorización de su etapa antes de programarlas. Los datos de balance
usados aquí son configuración de demostración, no balance oficial de Galactum.
Rama: feature/team3-m3-mining. Base de implementación: 2899abb. En el cierre del
2026-10-14, origin/integration/team3-m3 avanzó a a18c195 (vertical slice de combate).
Se consultó mediante fetch, sin incorporar sus cambios a esta rama. HEAD local y
remoto de minería: 374c833 (diseño inicial); implementación aún sin commit.
La extensión wire implementada está en contracts/sss_protocol_v1.md. Su convivencia
con combate requiere coordinación antes de integrar; ver informe de ETAPA 5.

Objetivo: nave propia → seleccionar asteroide → solicitar minería → SSS valida
→ extracción por tiempo/tasa → resultado autoritativo → cliente actualizado.

- **REGLA OFICIAL**: garantía del contrato vigente o requisito del handoff.
- **PROVISIONAL M3 - requiere aprobación**: propuesta concreta para la demo.
- **PENDIENTE DE DECISIÓN**: decisión externa que esta rama no resuelve.

Fuentes: AGENTS.md; contracts/sss_protocol_v1.md; docs/team3/OPEN_DECISIONS.md;
TEAM3-M3-SHIP-FLEET.md; handoff 01_M3_MINERIA_ASTEROIDES.docx y documento
Galactum_M3_Prompts_Mineria_Asteroides.docx proporcionados por el usuario.
La guía APT en lucas_mateo menciona exclusividad, extracción por tasa y reporte
idempotente como planificación; no proporciona balance canónico.

## 1. Arquitectura propuesta

**REGLA OFICIAL**: SSS autoritativo, GDScript tipado, configuración separada del
estado mutable, lógica separada de presentación y reutilización de Nave/Selección.

**PROVISIONAL M3 - requiere aprobación**:

- AsteroidConfig Resource: datos inmutables de demo.
- AsteroidState extends EntityState: identidad, posición, estado propio y
  serialización; integra EntityRegistry/SpatialHash/AoiEngine existentes.
- MiningOperation RefCounted tipado: progreso temporal y resultado terminal.
- MiningService RefCounted compuesto con SolarSystemWorld: validación,
  exclusividad, extracción y diario en memoria. Sin Autoload.
- MiningIntentState: preparación y solicitud pendiente local; consume IDs/modelos
  existentes y no constituye otro sistema de selección.

Mantener ciclo tick → publicar a todas las sesiones → acknowledge_changes.
Usar reloj SSS inyectable, como M2, sin Timer cliente que adjudique resultados.

## 2. Modelo y configuración del asteroide

**REGLA OFICIAL**: entity_id estable, kind asteroid, posición de mundo y
serialización por snapshot/delta; ningún NodePath como identificador.

**PROVISIONAL M3 - requiere aprobación**:

| Grupo | Campos |
| --- | --- |
| Identidad | entity_id, system_id, kind, position Vector2i |
| Configuración | asteroid_type, resource_type, initial_quantity, tasa y rango |
| Mutable | remaining_quantity, asteroid_state, occupant_entity_id nullable |
| Visible | identidad/posición, tipo/recurso, restante, estado y ocupante |

Estados: AVAILABLE, OCCUPIED, DEPLETED. Publicar asteroid_state separado del
state heredado; no dar comportamiento de viaje a asteroides. Resource compartido
sin ocupación/cantidades mutables; estado independiente para cada instancia.

Conservar IDs y posiciones del seed: (310,290) y (550,500).
Datos ficticios centralizados en .tres: tipo demo_asteroid, recurso demo_ore,
cantidad 10, tasa entera 1 unidad/segundo, rango euclídeo inclusivo 1 unidad.
Sin carga máxima, respawn ni cooldown para este slice; no son valores oficiales.

Ejemplo de entidad completa M3:

~~~json
{"entity_id":"asteroid-id","kind":"asteroid","system_id":"system-id",
 "position":[310,290],"asteroid_type":"demo_asteroid","resource_type":"demo_ore",
 "remaining_quantity":10,"asteroid_state":"AVAILABLE","occupant_entity_id":null}
~~~

## 3. Estados, reglas y extracción

Toda esta sección: **PROVISIONAL M3 - requiere aprobación**.

La nave conserva ANCHORED/TRAVELING. Minería es un bloque mining independiente,
nullable. No añadir MINING al estado de movimiento.

Operación: ACTIVE → COMPLETED por agotamiento; ACTIVE → CANCELLED por parada,
viaje válido o invalidación autoritativa. Las terminales no vuelven a ACTIVE.
Un actor tiene una operación activa y un asteroide un ocupante como máximo.
Validación y adquisición son atómicas en el SSS.

Iniciar requiere nave propia ANCHORED, mismo sistema, objetivo válido no agotado,
libre y distancia <= rango. TRAVELING se rechaza. No hay viaje automático.
Antes de extraer, revalidar existencia, estado y rango; invalidez cancela con
motivo INVALIDATED sin extraer fuera de rango.

Cancelación liquida unidades enteras hasta ese instante, descarta fracción final,
libera ocupación y conserva lo ya extraído. Agotamiento deja restante 0 y asteroide
DEPLETED visible, sin removed ni respawn.

Viaje aceptado cancela/liquida primero la minería con motivo TRAVEL_STARTED
y después inicia viaje M2 de forma indivisible. Viaje rechazado no cancela.
Conservar payload, timestamps, errores y ETA M2.

Desconectar no cancela: minería continúa en el SSS. Otra sesión del mismo jugador
observa/cancela la misma operación, sin otro actor. Reconectar/resume pide snapshot,
sin iniciar ni reenviar acciones automáticamente.

Extracción con enteros: objetivo = floor(tasa * tiempo_acumulado_ms / 1000).
Extraer sólo objetivo menos unidades ya contabilizadas, limitado al restante.
Conservar fracción entre ticks; acumular incrementos de tiempo >= 0 y guardar
último instante efectivo. Tick repetido/reloj hacia atrás no duplica extracción.
Ticks retrasados computan tiempo transcurrido, no cantidad de ticks.

## 4. Mensajes y versión propuestos

**REGLA OFICIAL**: JSON/WebSocket; seq por conexión en TODOS los mensajes;
server_time autoritativo; mundo exclusivamente por map_delta completo/incremental.
El contrato M2 team3-m2.0 permanece sin cambios silenciosos.

**PROVISIONAL M3 - requiere aprobación**: extensión team3-m3.0 para minería.
SSS acepta explícitamente M2 y M3; versión fijada al autenticar, respuestas con
versión de la sesión. M2 recibe serialización previa sin bloques nuevos ni acciones
de minería. Cliente configura versión; demo M3 y regresión M2 verificables.
Sin negociación genérica de capacidades ni ACK/retransmisión propia.

En ETAPA 2 el modelo/campos nuevos quedan internos y en pruebas: runtime M2
mantiene forma anterior hasta aprobar/documentar la extensión de ETAPA 3.

~~~json
{"type":"start_mining","protocol_version":"team3-m3.0",
 "request_id":"uuid-de-intencion","asteroid_entity_id":"asteroid-id"}
~~~

request_id: UUID textual, máximo 64 caracteres; conservarlo en reintentos.
SSS deriva actor de player_id autenticado como M2. Rechazar campos adicionales
de autoridad (player_id, actor entity_id, posición, cantidad, tasa, recompensa).

~~~json
{"type":"stop_mining","protocol_version":"team3-m3.0","mining_id":"operation-id"}
~~~

mining_id asignado por SSS; sólo el propietario puede parar esa operación.
Parada repetida devuelve el mismo resultado, sin volver a liquidar.
ID antiguo nunca detiene una operación nueva.

Aceptar/progresar/finalizar mediante map_delta de nave y asteroide.
No crear mining_started. Publicar bloques completos por el merge superficial:

~~~json
{"mining":{"mining_id":"operation-id","request_id":"uuid-de-intencion",
 "asteroid_entity_id":"asteroid-id","status":"ACTIVE","resource_type":"demo_ore",
 "rate_units_per_second":1,"started_ts":1780000000000,
 "updated_ts":1780000001000,"extracted_quantity":1},"last_mining_result":null}
~~~

~~~json
{"mining":null,"last_mining_result":{"mining_id":"operation-id",
 "request_id":"uuid-de-intencion","asteroid_entity_id":"asteroid-id",
 "status":"COMPLETED","reason":"DEPLETED","resource_type":"demo_ore",
 "quantity":10,"finished_ts":1780000010000}}
~~~

Resultados CANCELLED usan motivos USER_CANCELLED, TRAVEL_STARTED o INVALIDATED.
Conservar resultado anterior al iniciar otra operación; reemplazarlo sólo cuando
termine otra. Snapshot reconstruye operación activa y último resultado.

Replay activo republica estado actual por map_delta. Para una intención terminal
anterior al último resultado, mensaje mining_replay con request_id y resultado
original, siempre con sobre seq/server_time/protocol_version; no modifica mundo
ni sobrescribe operación actual. Parada terminal puede usar el mismo replay por
mining_id. No es otro mensaje de mundo ni un ACK de transporte.

Error usa type error, request_type, request_id cuando corresponda y mining_id en
parada. Códigos exclusivos:
MINING_INVALID_REQUEST, MINING_NOT_AUTHENTICATED, MINING_SHIP_NOT_FOUND,
MINING_SHIP_NOT_ANCHORED, MINING_ASTEROID_NOT_FOUND, MINING_OUT_OF_RANGE,
MINING_ASTEROID_OCCUPIED, MINING_DEPLETED, MINING_ALREADY_ACTIVE,
MINING_REQUEST_CONFLICT, MINING_OPERATION_NOT_FOUND, MINING_NOT_OWNER,
MINING_LIMIT_REACHED, MINING_SYSTEM_MISMATCH.
Versión incompatible usa el error de protocolo existente.
Errores/replay de minería resuelven sólo su intención coincidente; jamás Travel.
Pérdida de selección no confirma ni rechaza ninguna solicitud.

## 5. Validaciones, resultado e idempotencia

**PROVISIONAL M3 - requiere aprobación**:

1. Gateway valida versión, sesión autenticada, forma/tipos/longitudes/campos.
2. Diario por (player_id, request_id): mismo objetivo devuelve decisión original;
   distinto objetivo rechaza REQUEST_CONFLICT. Replay antes de validar rango o
   restante actual: no representa otra extracción.
3. Nueva intención valida actor derivado/ownership/sistema, tipo de objetivo,
   ANCHORED, rango, restante, exclusividad y límite; registrar/ocupar atómicamente.
4. Registrar solicitudes start bien formadas autenticadas, incluidos rechazos de
   negocio. Mismo UUID conserva decisión; nuevas condiciones requieren UUID nuevo.
5. Acumulador impide extracción duplicada; guardia terminal liquida una sola vez.
   Resultado estable por mining_id; parada valida propietario incluso en replay.

Diario en memoria por vida del proceso. Límite configurable demo: 256 intenciones
por jugador. No expulsar claves: una intención vieja no debe reiniciarse
silenciosamente. Al alcanzar límite rechazar nuevos inicios; paradas/replays siguen permitidos.
No guardar paquetes malformados/no autenticados. No garantizar idempotencia tras
reiniciar SSS; resultado y mundo también son efímeros.

**REGLA OFICIAL**: desacoplar dependencias económicas si se utilizan.
**PROVISIONAL M3 - requiere aprobación**: resultado tipado sin acreditar balances,
inventario ni progreso; frontera simple sustituible para Equipo 2. No crear un
provider sin uso. Cliente deduplica avisos por mining_id y nunca acredita recursos.
**PENDIENTE DE DECISIÓN**: economy.apply real, retención/persistencia del diario,
recovery e idempotencia entre procesos. Si se exige acreditación para M3, revisar
diseño antes de implementar ETAPA 3; no asumirla.

## 6. Sincronización, AOI y recuperación

**REGLA OFICIAL**: added completo; updated parcial por entity_id; removed invalida
visibilidad, no equivale a destrucción. Bloques anidados se sustituyen completos;
mining null limpia estado obsoleto.

**PROVISIONAL M3 - requiere aprobación**: especializar serialización de asteroides
para publicar restante/ocupación en updates. Preservar serialización M2 de naves.
Publicar cambios reales; deduplicar entity_id en mensaje; no drenar ChangeSet
por sesión. Estado ACTIVE y terminal debe llegar también en full snapshot.

Brecha observada al leer delta_for: sólo recorre entidades cambiadas, usando
centro AOI actual. Asteroide inmóvil puede entrar/salir por movimiento de la
nave observadora sin added/removed. ETAPA 2 verifica y corrige esta brecha en
la publicación por sesión con pruebas del mundo y de WebSocket real.
Propuesta ETAPA 2: visible_ids por sesión, inicializado en snapshot; comparar AOI
actual con réplica previa al publicar. Entradas completas; salidas por ID; updates
sólo de entidades conocidas aún visibles. Reiniciar en conexión/snapshot y
conservar API M2; ninguna segunda autoridad AOI. Requiere aprobación explícita
como parte del alcance de sincronización.

removed limpia selección/objetivo preparado, no cancela operación autoritativa.
La nave propia conserva operación/resultado. Desync bloquea nuevas acciones hasta
snapshot; no presupone rechazo. Reconexión reconstruye desde estado SSS.

## 7. Cliente y UX mínima

**REGLA OFICIAL**: misma ShipSelectionState compartida con WorldDebugView.
Reconsultar ShipRepresentation/WorldState tras cambios, sin copia como estado vivo.

**PROVISIONAL M3 - requiere aprobación**:

1. Seleccionar nave propia; conservar sólo actor_entity_id como contexto de acción.
2. Botón Elegir asteroide cambia modo de input de acción; misma selección única.
3. Mouse/touch selecciona asteroide; reconsultar actor con get_ship, propiedad
   con is_owned_by y nave propia con get_ship_for_player. SSS valida nuevamente.
4. Minar envía una intención; mostrar pendiente, rechazo o operación recibida.
5. Mostrar restante, ocupación, tasa y extraído del SSS; no escribir WorldState
   ni reducir recursos desde presentación.
6. Detener minería usa mining_id activo; mostrar resultado una sola vez.

Una sola solicitud de acción pendiente por cliente (viaje/inicio/parada).
Mantener una solicitud start_travel pendiente y confirmación/ETA M2.
Viaje disponible mientras extrae; SSS cancela minería al aceptarlo.
removed/actor ausente o ajeno invalidan preparación; operación observada aunque
no esté seleccionada. Reconexión/resume limpian contexto/pending, conservando
identidad de última intención incierta para replay explícito tras snapshot, sin
reenvío automático. Sin UI artística, flotas nuevas ni inventario.

## 8. Archivos propuestos

Sólo este documento se crea en ETAPA 1. Rutas world/config siguientes en server/sss.

| Etapa | Crear | Modificar y razón |
| --- | --- | --- |
| 2 | config/asteroid_config.gd y .tres; world/asteroid_state.gd; tests asteroide | mock_world_seed, solar_system_world, gateway: modelo/serialización/AOI, mantener runtime M2 |
| 3 | world/mining_operation.gd, mining_service.gd; config/mining_config.gd y .tres; tests minería | mundo/tick, entity_state nave, gateway/configuración; añadir sección M3 al contrato tras aprobación |
| 4 | modules/team3/mining/mining_intent_state.gd; tests cliente/runner M3 | sss_connection, client_connection_config/default .tres, app/main.gd/.tscn, world_debug_view: protocolo/input/UI |
| 5 | guía/demo o runner si faltan | diseño y docs/TESTING.md con evidencia real |

Conservar .uid correspondientes. WorldState sólo cambia si las consultas existentes
no bastan. No reemplazar ShipRepresentation ni ShipSelectionState.
Pruebas multiusuario inyectan autenticador de test; no ampliar auth de runtime
únicamente para probar dos jugadores.

## 9. Pruebas previstas

| Grupo | Casos |
| --- | --- |
| Modelo | IDs estables, datos/estado separados, instancias independientes, serialización |
| Réplica | full/add/updates parciales/null/removed/reconstrucción; entrada/salida AOI por observador/objetivo; dos sesiones |
| Inicio | válido; payload malformado; sin auth; actor inexistente/ajeno; objetivo ausente/tipo incorrecto; sistema/estado/rango inválidos |
| Exclusividad | dos jugadores; actor ya activo; liberación de ocupante |
| Extracción | fracciones, mismo tiempo, reloj atrás, tick retrasado, agotamiento exacto, restante no negativo |
| Terminales | cancelación parcial/cero; parada duplicada/ajena; ID antiguo; viaje aceptado/rechazado |
| Idempotencia | replay activo/terminal/rechazado; objetivo cambiado; operación nueva en curso; límite diario |
| Conexión | continuar desconectado, dos sesiones mismo jugador, snapshot/replay, desync/resume simulado |
| Cliente | selección única; mouse/touch; pending; rechazo correlacionado; progreso/resultado; removed/limpieza; convivencia Travel |
| Regresión | M1 puras; cuatro cliente M2; seis SSS viaje; tres Nave/Selección; expectativas M2 preservadas |
| E2E | SSS real + escena: viajar cerca, elegir/minar, completar/cancelar, desconectar/reconectar/replay |

Ejecutar por proyecto: godot --headless --path . --script res://tests/<test>.gd
o --path server/sss. Import previo si Godot lo necesita. E2E inicia SSS nuevo y
registra rama/HEAD, Godot, comando, código de salida y marcador.
Smoke M0/M1 históricos no prueban runtime M2/M3 actual.
Touch simulado PC no valida Android físico/layout/background: prueba manual aparte.
Ninguna prueba ejecutada en ETAPA 1.

## 10. Contradicciones, reglas pendientes y dependencias

- APT planifica JWT/Redis/economía y otros sistemas; handoff limita este slice.
  No incorporar esa infraestructura por usar la guía como referencia.
- OPEN_DECISIONS mantiene autoridad TimerService/SSS, persistencia y unidades
  abiertas. Tiempo SSS/unidades existentes sólo propuesta de demo, sin resolver
  contratos de producción.
- Introducción del contrato llama actual a M1, pero sección M2/código usan M2.
  Deuda documental; no modificar silenciosamente.
- TEAM3-M3-SHIP-FLEET termina diciendo merge pendiente, aunque referencia local
  M3 ya contiene esos commits; no modificar su documentación histórica aquí.
- Serialización específica y AOI de asteroides estáticos son brechas técnicas
  propuestas para revisión, no reglas oficiales nuevas.
- Combat/PvE comparte mundo/gateway/UI: coordinar versión/campos y diffs.
  No implementar interrupción por combate, daño, enemigos ni spawning.
- **PENDIENTE DE DECISIÓN**: catálogo/balance oficial, capacidad/costos,
  persistencia/recovery y relación combate/minería.

## 11. Aprobación y etapas siguientes

Revisar expresamente: protocolo dual M2/M3; modelo/campos; datos demo/rango;
exclusividad/tasa; viaje cancela; desconexión continúa; resultado sin acreditación;
replay/diario limitado; corrección AOI; modo Elegir asteroide.
Todas son propuestas pendientes, no requisitos oficiales ni implementación.

Después de revisión/correcciones:
ETAPA 2 modelo/sincronización → informe/pausa;
ETAPA 3 aprobada: ciclo SSS/contrato/regresión M2 → informe/pausa;
ETAPA 4 aprobada: cliente/UX/E2E → informe/pausa;
ETAPA 5 aprobada: suite/auditoría/demo/recomendación MERGE SÍ/NO → pausa.
No commit, push, merge ni PR en estas etapas salvo autorización explícita del usuario.
El usuario autorizó incorporar y subir el diseño de ETAPA 1, y posteriormente
pidió continuar con ETAPAS 2, 3 y 4. No avanzar a ETAPA 5 ni publicar esta
implementación sin la autorización correspondiente al flujo por etapas.

## 12. Informe de ETAPA 2 — implementado y verificado

Ejecución: 2026-10-14, Windows/PC, Godot 4.6.2 stable. Baseline HEAD 374c833;
resultados sobre cambios locales de ETAPA 2 sin commit. No se modificaron el
contrato compartido, la versión activa, las reglas de viaje ni la UI de minería.

### Modelo y configuración implementados

- AsteroidConfig y default_asteroid_config.tres centralizan los datos demo.
- AsteroidState separa configuración copiada, identidad, cantidad y ocupante.
  Deriva AVAILABLE/OCCUPIED/DEPLETED sin introducir estados nuevos de viaje.
- set_resource_state valida cantidades y coherencia del ocupante; una mutación
  inválida no altera el modelo. No ejecuta extracción ni exclusividad de acciones.
- SolarSystemWorld.set_asteroid_resource_state valida tipo, actualiza datos y
  registra cambios únicamente cuando hay una diferencia efectiva.
- Seed preserva los dos IDs y posiciones y los registra como AsteroidState.
  IDs vacíos/duplicados no alteran ni el índice ni el registro existente.

### Sincronización implementada

full_snapshot_for/delta_for conservan API anterior y por defecto serialización M2.
El argumento interno include_asteroid_data habilita campos del modelo para las
pruebas; no es un campo de protocolo ni habilita M3 en red durante ETAPA 2.
AsteroidState tiene serialización completa y updates parciales con null explícito
para liberar ocupante. M2 mantiene su representación anterior.

delta_for_session compara el AOI autoritativo actual con visible_ids de la sesión:
added completo para entradas, removed para salidas y updated para cambios de
entidades conocidas. Deduplica updates por entity_id. La API histórica delta_for
se conserva para consumidores previos; el gateway usa delta_for_session.

Gateway inicializa el conjunto visible al enviar snapshot, lo actualiza sólo
tras encolar exitosamente el mensaje y espera snapshot antes de publicar deltas.
Reautenticación/reconexión reinician esa réplica. Ninguna sesión drena ChangeSet;
el runtime mantiene tick/publicación/acknowledge. removed por AOI no destruye
AsteroidState. El cliente existente reconstruye datos y limpia selección sin
modificaciones de producción en esta etapa.

### Archivos de esta etapa

Creación:

- server/sss/config/asteroid_config.gd y su .uid.
- server/sss/config/default_asteroid_config.tres.
- server/sss/world/asteroid_state.gd y su .uid.
- server/sss/tests/asteroid_state_test.gd y su .uid.
- server/sss/tests/asteroid_world_sync_test.gd y su .uid.
- server/sss/tests/asteroid_gateway_sync_test.gd y su .uid.
- tests/m3_asteroid_replica_test.gd y su .uid.

Modificación:

- server/sss/mock/mock_world_seed.gd: configuración demo de asteroides.
- server/sss/world/solar_system_world.gd: modelo, serialización y delta por réplica.
- server/sss/network/websocket_gateway.gd: visibilidad de sesión y envío confirmado.
- Este documento: estado, alcance real y evidencia.

### Resultado de cada prueba

Las 26 pruebas siguientes terminaron con código 0 y su marcador OK.

| Proyecto | Prueba | Resultado |
| --- | --- | --- |
| SSS | asteroid_state_test | ASTEROID_STATE_TEST_OK |
| SSS | asteroid_world_sync_test | ASTEROID_WORLD_SYNC_TEST_OK |
| SSS/WebSocket real | asteroid_gateway_sync_test | ASTEROID_GATEWAY_SYNC_TEST_OK |
| Cliente | m3_asteroid_replica_test | M3_ASTEROID_REPLICA_TEST_OK |
| Cliente | m1_client_world_state_test | M1_CLIENT_WORLD_STATE_TEST_OK |
| Cliente | m1_sss_connection_sequence_test | M1_SSS_CONNECTION_SEQUENCE_TEST_OK |
| Cliente | m2_sss_connection_test | M2_SSS_CONNECTION_TEST_OK |
| Cliente | m2_travel_intent_test | M2_TRAVEL_INTENT_TEST_OK |
| Cliente | m2_travel_projection_test | M2_TRAVEL_PROJECTION_TEST_OK |
| Cliente | m2_world_debug_view_test | M2_WORLD_DEBUG_VIEW_TEST_OK |
| Cliente | m3_ship_representation_test | M3_SHIP_REPRESENTATION_TEST_OK |
| Cliente | m3_ship_selection_test | M3_SHIP_SELECTION_TEST_OK |
| Cliente + SSS real | m3_ship_scene_test | M3_SHIP_SCENE_TEST_OK |
| SSS | world_snapshot_test | SSS_WORLD_TEST_OK |
| SSS | entity_registry_test | ENTITY_REGISTRY_TEST_OK |
| SSS | spatial_hash_test | SPATIAL_HASH_TEST_OK |
| SSS | aoi_test | AOI_TEST_OK |
| SSS | world_snapshot_multi_test | WORLD_SNAPSHOT_MULTI_TEST_OK |
| SSS | world_delta_test | WORLD_DELTA_TEST_OK |
| SSS | changeset_lifecycle_test | CHANGESET_LIFECYCLE_TEST_OK |
| SSS | travel_math_test | TRAVEL_MATH_TEST_OK |
| SSS | travel_start_test | TRAVEL_START_TEST_OK |
| SSS | travel_snapshot_test | TRAVEL_SNAPSHOT_TEST_OK |
| SSS | travel_delta_test | TRAVEL_DELTA_TEST_OK |
| SSS | travel_tick_test | TRAVEL_TICK_TEST_OK |
| SSS | travel_aoi_test | TRAVEL_AOI_TEST_OK |

entity_registry_test emite errores intencionales por ID duplicado y actualización
de entidad inexistente; terminó OK. No se ocultaron fallos del motor en pruebas
nuevas. El primer intento del runner temporal de escena falló al leer un log
abierto por el SSS; se corrigió la lectura compartida y el siguiente pasó.

### Cómo repetir la verificación

Desde raíz, godot representa el ejecutable de Godot 4.6.2 instalado localmente:

~~~powershell
godot --headless --editor --path server/sss --import
godot --headless --editor --path . --import
godot --headless --path server/sss --script res://tests/asteroid_state_test.gd
godot --headless --path server/sss --script res://tests/asteroid_world_sync_test.gd
godot --headless --path server/sss --script res://tests/asteroid_gateway_sync_test.gd -- --port=19322
godot --headless --path . --script res://tests/m3_asteroid_replica_test.gd
~~~

Las regresiones unitarias se ejecutan individualmente como indica docs/TESTING.md.
Para m3_ship_scene_test, iniciar un SSS nuevo en otra terminal y esperar SSS_READY:

~~~powershell
godot --headless --path server/sss -- --port=19323
# Otra terminal:
godot --headless --max-fps 60 --path . --script res://tests/m3_ship_scene_test.gd -- --port=19323
~~~

Cerrar el SSS de esa prueba al terminar. asteroid_gateway_sync_test crea y cierra
su propio gateway, así que necesita puerto libre y no un SSS externo.

### Riesgos y pendientes para ETAPA 3

- No se implementaron start/stop, extracción, acreditación, diario ni UX de minería.
- team3-m3.0 y sus campos en red requieren implementación/documentación de ETAPA 3;
  en esta etapa un cliente M2 ve asteroides con la forma previa.
- La réplica por sesión consulta el AOI y serializa sus entidades al publicar;
  funciona en la demo, pero escala/rendimiento de producción no se midieron.
- Godot informó Android build-tools no disponible al importar cliente. No se
  generó APK ni se validó Android físico, layout o background/resume real.
- Coordinar cambios de mundo/gateway con Combat/PvE antes de integrar; no se
  actualizaron ni mezclaron otras ramas durante esta implementación.
- Esperar aprobación de ETAPA 3 y conservar las decisiones pendientes de
  persistencia, economía real y balance oficial.

## 13. Informe de ETAPA 3 — minería autoritativa SSS

El usuario autorizó esta etapa después del informe de ETAPA 2. Implementado
2026-10-14 en Windows, Godot 4.6.2 stable; baseline HEAD 374c833 y cambios locales
de ETAPAS 2/3, sin commit/push/merge. La UI cliente permanece en M2 hasta ETAPA 4.
El informe anterior describe la evidencia histórica de ETAPA 2, no pendientes
que sigan bloqueando la implementación de servidor aquí registrada.

### Flujo y validaciones implementados

Gateway M3 valida autenticación y campos/tipos; rechaza datos de autoridad del
cliente. MiningService deriva nave propia, valida sistema, tipo de objetivo,
ANCHORED, rango, restante y ocupación. Exclusividad se adquiere junto con el
registro de operación. Dos jugadores compiten por el mismo estado autoritativo.

MiningOperation conserva IDs, tasa/rango, tiempo, cantidad extraída y resultado
terminal. ACTIVE termina COMPLETED/DEPLETED o CANCELLED con USER_CANCELLED,
TRAVEL_STARTED o INVALIDATED. Minería no altera ANCHORED/TRAVELING. No se
implementaron inventario, balances, acreditación económica ni progresión.

El tick calcula unidades enteras por tiempo acumulado, conserva fracción y limita
al restante. Timestamp repetido o hacia atrás no repite extracción. Cancelar
liquida hasta el instante recibido y libera ocupante. Viaje válido liquida/cancela
antes de iniciar TRAVELING; viaje rechazado no cambia minería. Si se agota al
liquidar antes de parar/viajar, prevalece resultado COMPLETED/DEPLETED.

Desconexión no cambia ciclo. Reconexión y otra sesión del mismo jugador recuperan
el mismo mining_id mediante snapshot. Invalidar existencia/propiedad/sistema/
estado/rango cancela sin extraer fuera de condiciones. Resultado se conserva en
diario aun si desaparece la nave y no puede publicarse su actualización.

### Idempotencia y frontera de resultado

Diario por jugador/request_id: una intención no inicia dos procesos. Objetivo
distinto con misma clave rechaza conflicto; UUID nuevo reevalúa condiciones.
Decisiones rechazadas también se conservan. Límite configurable 256 sin expulsar
claves; lleno permite paradas/replays y rechaza nuevos inicios.

Extracción contabiliza únicamente diferencia pendiente. Finalización tiene guardia
terminal. Resultado se devuelve como copia; replays/paradas antiguas no alteran
operación actual, restante ni último resultado. No hay operación económica que
pueda acreditarse dos veces: resultado es la frontera sustituible para Equipo 2.
La garantía es efímera, no persiste tras reiniciar SSS.

### Protocolo y sincronización

Se añadió sección TEAM3-M3-MINING a contracts/sss_protocol_v1.md sin reescribir
el acuerdo M2. SSS soporta ambas versiones por sesión, fijadas al autenticar.
En M3: start_mining, stop_mining, error correlacionado con códigos MINING_* y
mining_replay terminal. Estado/aceptación/progreso/fin por map_delta; snapshot
incluye minería activa y último resultado. Objetos anidados completos y null
explícito al finalizar. Replay no escribe un resultado viejo en el estado actual.
M2 conserva sobre/payload de viajes y omite todos los campos nuevos de minería.

### Archivos de ETAPA 3

Creación:

- server/sss/config/mining_config.gd y .uid; default_mining_config.tres.
- server/sss/world/mining_operation.gd y .uid; mining_service.gd y .uid.
- server/sss/tests/mining_lifecycle_test.gd y .uid.
- server/sss/tests/mining_validation_test.gd y .uid.
- server/sss/tests/mining_idempotency_test.gd y .uid.
- server/sss/tests/mining_gateway_test.gd y .uid.

Modificación respecto de ETAPA 2:

- server/sss/config/sss_config.gd: configura el diario de minería.
- server/sss/world/entity_state.gd: bloques independientes de minería/resultado.
- server/sss/world/solar_system_world.gd: servicio, tick, viaje y serialización M3.
- server/sss/network/websocket_gateway.gd: versiones, validación y acciones M3.
- server/sss/world/asteroid_state.gd: comentarios de compatibilidad actualizados.
- contracts/sss_protocol_v1.md: extensión documentada.
- Este diseño: estado e informe.

### Pruebas y resultados de ETAPA 3

Las cuatro nuevas y las 26 regresiones terminaron con código 0 y marcador OK:

| Prueba nueva | Resultado | Cobertura principal |
| --- | --- | --- |
| mining_lifecycle_test | MINING_LIFECYCLE_TEST_OK | fracción, tiempo repetido/retroceso, tick retrasado, cancelación, agotamiento, snapshots y resultado estable |
| mining_validation_test | MINING_VALIDATION_TEST_OK | actor/objetivo/sistema/estado/rango, dos jugadores, parada ajena, invalidación y viaje/minería |
| mining_idempotency_test | MINING_IDEMPOTENCY_TEST_OK | proceso único, conflicto, replay/stop antiguo, copia de resultado, rechazo original, cuota e invalidación |
| mining_gateway_test | MINING_GATEWAY_TEST_OK | WebSocket real, dos jugadores, versiones M2/M3, payload inválido/autoridad falsa, desconexión/reconexión, extracción y replay |

Se repitieron las 26 pruebas enumeradas en el informe de ETAPA 2, incluidas las
cuatro de asteroides, M1, los diez tests de viaje M2 y las tres de Nave/Selección.
Todas dieron el mismo marcador OK. m3_ship_scene_test usó SSS nuevo real en puerto
19323: selección touch simulada, viaje, reconexión, ETA reconstruible y llegada.
entity_registry_test mantiene los errores intencionales documentados anteriormente.

Comandos de pruebas nuevas, desde raíz:

~~~powershell
godot --headless --editor --path server/sss --import
godot --headless --path server/sss --script res://tests/mining_lifecycle_test.gd
godot --headless --path server/sss --script res://tests/mining_validation_test.gd
godot --headless --path server/sss --script res://tests/mining_idempotency_test.gd
godot --headless --path server/sss --script res://tests/mining_gateway_test.gd -- --port=19324
~~~

mining_gateway_test inicia/cierra gateway propio; necesita puerto libre y no un
SSS externo. Los demás comandos y la escena se repiten como en ETAPA 2.

### Riesgos y pendientes de cliente

- No se modificaron SssConnection, TravelIntentState ni escena/UI de producción.
  Cliente M2 sigue funcionando; cliente M3/selección/UX requieren ETAPA 4.
- ETAPA 4 debe correlacionar errores/replays con pending, deduplicar avisos por
  mining_id, limpiar contexto al reconectar y reconstruir mediante snapshot.
- No garantías tras reinicio SSS ni integración con economy.apply; decisiones
  oficiales de balance, capacidad/costos y combate/minería siguen pendientes.
- Diario puede llenarse en sesiones largas: se rechaza nuevo inicio de forma
  explícita, sin expulsión que rompa idempotencia. No se probó carga de producción.
- Compatibilidad de Android físico/layout/background permanece pendiente.
- Cambios en mundo/gateway/contrato requieren coordinación con Combat/PvE al
  integrar después. No se mezclaron ramas ni se añadieron reglas de combate.
- Detenerse tras este informe; esperar autorización de ETAPA 4.

## 14. Informe de ETAPA 4 — cliente y flujo funcional

Autorizada por el usuario después del informe de ETAPA 3. Verificación final en
Windows/PC, Godot 4.6.2 stable, sobre HEAD 374c833 con cambios locales de ETAPAS
2–4 sin commit/push/merge. Los informes previos conservan sus resultados históricos.

### Flujo, selección y UI implementados

MiningIntentState guarda actor/objetivo como contexto de acción, no una segunda
selección. Actor se consulta por WorldState.get_ship/ShipRepresentation; la nave
propia por get_ship_for_player. Se comparte la misma ShipSelectionState de M3.

Seleccionar nave propia → Elegir asteroide → click/tap del asteroide → Minar →
pendiente → aceptación/rechazo → progreso SSS → Detener minería o agotamiento →
resultado. UI muestra restante/ocupación del objetivo, cantidad extraída, tasa y
resultado, sin modificar WorldState ni acreditar inventario/economía.

WorldDebugView agrega modo de elección de asteroide que filtra únicamente esos
objetivos, reutilizando mouse/touch y selección existentes. En selección normal,
un empate exacto de posición prioriza nave sobre otro tipo; permite seleccionar
nave superpuesta al asteroide después de viajar/reconectar. En modo asteroide se
elige el asteroide. El modo de coordenadas de viaje mantiene su comportamiento.

Panel de acciones con botones de altura mínima 48, FlowContainer para filas
ajustables y ScrollContainer para acceder a contenido en pantallas estrechas.
Se verificaron propiedades de layout a 360x720 en headless; no es inspección
visual ni validación de un dispositivo físico.

### Pendientes, recuperación y convivencia con Travel

SssConnection conserva payload M2 por defecto cuando no recibe configuración;
la configuración de demo usa team3-m3.0. Cada conexión usa la versión configurada
para auth, viaje, minería y validación de respuestas. Existe override de desarrollo
--protocol=team3-m2.0 para la ruta legacy y sus pruebas.

Una sola acción de red pendiente entre viaje/inicio/parada. Errores MINING_* se
correlacionan por request_type y request_id/mining_id, sin resolver Travel. Replay
terminal se valida y correlaciona antes de resolver su intención. Perder selección
o salir del AOI no confirma/rechaza solicitudes. Resultado se notifica una sola
vez por mining_id; repetir snapshots/reconexión no repite efectos ni avisos.

Desconexión/resume limpian selección, contexto y réplica visible. Se conserva una
intención minera incierta y sus IDs para recuperación explícita. El snapshot puede
probar su aceptación/resultado y despejarla; si no, aparece Recuperar solicitud
para reenviar la misma intención, sin generar UUID nuevo. No se reenvía sola.
Desync bloquea nuevas acciones hasta reconstruir snapshot. La minería autoritativa
activa se observa y se puede parar aun sin seleccionar otra vez la nave.

### Archivos de ETAPA 4

Creación:

- modules/team3/mining/mining_intent_state.gd y .uid.
- tests/m3_mining_intent_test.gd y .uid.
- tests/m3_mining_connection_test.gd y .uid.
- tests/m3_mining_input_test.gd y .uid.
- tests/m3_mining_scene_test.gd y .uid.
- server/sss/tests/mining_scene_server.gd y .uid, fixture E2E de viaje acelerado.
- tools/run_m3_mining_smoke.ps1, que inicia/cierra la fixture y ejecuta la escena.

Modificación respecto de ETAPA 3:

- config/client_connection_config.gd y default_client_connection.tres: versión.
- modules/team3/network/sss_connection.gd: acciones M3, correlación y pending común.
- modules/team3/world/world_debug_view.gd: modo asteroide y empate de selección.
- app/main.gd y app/main.tscn: integración y UI mínima adaptable.
- contracts/sss_protocol_v1.md: nota de versión actual del cliente, sin mensajes nuevos.
- Este documento: alcance, resultados y demo.

WorldState, ShipRepresentation, ShipSelectionState y TravelIntentState se reutilizan
sin modificar sus archivos de producción. No se agregaron Autoloads.

### Pruebas y resultados finales

34 pruebas distintas pasan; 35 ejecuciones porque la escena de viaje también se
ejecutó explícitamente bajo ambas versiones. Todas terminaron código 0 y marcador OK.

| Prueba nueva | Resultado | Qué cubre |
| --- | --- | --- |
| m3_mining_intent_test | M3_MINING_INTENT_TEST_OK | actor/objetivo, selección única, pending, removed, rechazo/replay correlacionados, recuperación y resultados deduplicados |
| m3_mining_connection_test | M3_MINING_CONNECTION_TEST_OK | payload mínimo, versión, bloqueo entre acciones, errores independientes, desync y snapshot |
| m3_mining_input_test | M3_MINING_INPUT_TEST_OK | mouse/touch, entidades superpuestas, pending, removed y retorno al modo Travel |
| m3_mining_scene_test | M3_MINING_SCENE_TEST_OK | escena + SSS real: layout estrecho, rechazo por rango, viaje, minería, reconexión, cancelación, agotamiento y desync |

Las 30 pruebas del informe de ETAPA 3 se repitieron y dieron OK. La prueba
m3_ship_scene_test se ejecutó en M2 y M3 con SSS nuevo normal en puerto 19323;
preserva selección, cancelación de destino, viaje, reconexión, trayectoria/ETA y
llegada. No se actualizaron expectativas de regresiones para esconder cambios.

La E2E nueva detectó problemas de layout estrecho y selección superpuesta tras
reconexión: se corrigieron y la ejecución final completa pasó. La fixture acelera
sólo viaje a 600 unidades/minuto; conserva seed, tasa/cantidad de minería y runtime
real de gateway/tick. El servidor normal conserva velocidad M2 de 10 unidades/min.

Comandos de pruebas nuevas, desde raíz:

~~~powershell
godot --headless --editor --path . --import
godot --headless --editor --path server/sss --import
godot --headless --path . --script res://tests/m3_mining_intent_test.gd
godot --headless --path . --script res://tests/m3_mining_connection_test.gd
godot --headless --path . --script res://tests/m3_mining_input_test.gd
powershell.exe -NoProfile -File tools/run_m3_mining_smoke.ps1 -GodotPath C:/ruta/a/godot.exe -Port 19325
~~~

Reemplazar la ruta de ejemplo por el ejecutable instalado. El runner reserva
puerto libre, inicia fixture oculta y siempre cierra su propio proceso. No iniciar
otro SSS en ese puerto. Logs de fixture se guardan en la carpeta temporal del SO.
Marca final M3_MINING_SCENE_TEST_OK y eventos CLIENT_M3_MINING_RESULT_OK; la escena
de viaje conserva M3_SHIP_SCENE_TEST_OK bajo ambas versiones.

### Demo manual reproducible con servidor normal

~~~powershell
# Terminal 1:
godot --headless --path server/sss
# Terminal 2:
godot --path .
~~~

1. Esperar conexión/snapshot. La configuración cliente de demo usa M3.
2. Seleccionar la nave propia en (300,300); elegir destino (310,290) y confirmar viaje.
3. Esperar llegada ANCHORED. Con la velocidad M2 normal, ese viaje demora unos
   85 segundos; observar ETA. La fixture de prueba acelera sólo este tramo.
4. Pulsar Elegir asteroide y tocar el marcador superpuesto en (310,290).
5. Pulsar Minar; observar pendiente, progreso y actualizaciones autoritativas.
6. Reconectar durante minería: selección se limpia y operación se reconstruye.
7. Detener minería para resultado parcial o esperar agotamiento (10 segundos
   de extracción total con el depósito demo completo). Resultado aparece una vez.
8. Repetir selección por mouse/touch y verificar scroll en pantallas estrechas.

Minar antes de acercarse muestra rechazo explicado. Repetir una extracción total
requiere SSS nuevo porque esta demo no incorpora respawn. Para comprobar M2:
godot --path . -- --protocol=team3-m2.0; panel de minería queda oculto.

### Riesgos y pendientes para ETAPA 5

- Validación de lógica/input simulados y layout headless en PC, sin APK ni Android
  físico, orientación definitiva o background/resume real del SO. Importación
  sigue informando Android build-tools no disponible.
- MiningIntentState conserva incertidumbre/deduplicación dentro de la instancia
  cliente; no persiste tras cerrar la aplicación. SSS tampoco persiste su diario.
- Economía real, balance oficial, capacidad/costos e interrupción por combate
  permanecen fuera de este slice o pendientes de decisión.
- Falta auditoría final del diff, matriz de pruebas/documentación de cierre y
  recomendación explícita de integración. No se ejecutó merge ni se abrió PR.
- Esperar autorización de ETAPA 5 y no añadir funcionalidades por iniciativa propia.

## 15. Informe de cierre — ETAPA 5

### Resultado y clasificación final

Cierre autorizado por el usuario y realizado el 2026-10-14. Esta etapa modifica
sólo este documento y docs/TESTING.md; no agrega gameplay.

| Clasificación | Alcance |
| --- | --- |
| **IMPLEMENTADO** | Asteroides autoritativos, configuración separada, estados/cantidad/ocupación, snapshot/delta/AOI; ciclo inicio/progreso/parada/agotamiento; validaciones y exclusividad; resultado único y replay; UI mínima, mouse/touch, recuperación y convivencia con Travel |
| **PROVISIONAL M3** | demo_ore, cantidad 10, tasa 1/s, rango euclidiano inclusivo 1, sin respawn/capacidad/cooldown; diario en memoria hasta 256 intenciones/jugador; minería continúa desconectado; viaje aceptado cancela con extracción parcial; M3 opt-in por sesión y cliente demo M3 |
| **PENDIENTE DE DECISIÓN** | Balance oficial, flotas, economía/capacidad/costos, persistencia, política definitiva de desconexión, interrupción por combate y convivencia del contrato con la nueva integración de Combat |
| **FUERA DE ALCANCE** | Acreditar inventario/economía, PvE/combate nuevo, autenticación real, backend completo, respawn, APK y validación en dispositivo Android |

Lo implementado aplica las reglas provisionales aprobadas para esta demo; no las
convierte en reglas oficiales de Galactum.

### Auditoría de responsabilidades y regresiones

- MiningService posee validación, exclusividad, tiempos, extracción, diario y
  finalización. MiningOperation congela un resultado; la UI sólo muestra datos
  autoritativos y comunica intenciones.
- AsteroidConfig/MiningConfig contienen configuración; AsteroidState mantiene
  estado por entidad. No se comparte cantidad/ocupación mutable entre Resources.
- WorldState, ShipRepresentation, ShipSelectionState y TravelIntentState no
  cambiaron. MiningIntentState usa su selección; no crea una segunda autoridad.
- No se agregan Autoloads ni una referencia circular World → MiningService → World.
  Servicios reciben sólo las dependencias utilizadas.
- El gateway deriva actor desde la sesión y rechaza campos de autoridad del cliente.
  Validación de seq sigue centralizada en SssConnection, con snapshot tras desync.
- M2 mantiene su forma wire; la extensión minera se publica sólo en sesiones M3.
  added incluye entidad completa; updated reemplaza bloques mining/result completos;
  removed elimina la réplica sin inventar un resultado.
- El cálculo usa timestamps y cantidad acumulada, limita extracción al remanente y
  no vuelve a extraer en replay/tick repetido. Stop antiguo no cancela operación nueva.
- Se revisaron diff, archivos nuevos y configuración: sin secretos, builds ni
  temporales añadidos; AGENTS.md existente permanece intacto. git diff --check pasa.
  Las regresiones mantienen sus expectativas originales.

### Pruebas finales ejecutadas

Entorno: Windows, Godot 4.6.2.stable.official.71f334935, base 2899abb, HEAD 374c833
más cambios locales. Ambas importaciones dieron código 0. Total **34 pruebas
distintas / 35 ejecuciones**, todas con código 0 y marcador OK:

| Grupo | Pruebas | Ejecuciones | Resultado |
| --- | --- | --- | --- |
| Cliente: réplica, secuencia, Travel, nave/selección, asteroide e intenciones/input/red minera | 12 | 12 | OK |
| SSS: registro/índice/AOI, snapshot/delta, Travel, asteroides y minería/gateway | 20 | 20 | OK |
| Escena real de nave + SSS normal bajo M2 y M3 | 1 | 2 | M3_SHIP_SCENE_TEST_OK |
| Escena real de minería + fixture SSS con sólo Travel acelerado | 1 | 1 | M3_MINING_SCENE_TEST_OK |

La matriz individual y comandos están en [docs/TESTING.md](../TESTING.md).
La escena minera verificó rango rechazado, viaje, progreso, reconexión, parada
con cantidad 1 y posterior agotamiento con 9, resultado deduplicado y recuperación
por gap de secuencia. La demo manual normal permanece en ETAPA 4 de este documento.

entity_registry_test emite dos push_error deliberados para entradas inválidas;
termina con ENTITY_REGISTRY_TEST_OK. Smoke E2E M0/M1 no se ejecutaron por versión
histórica; sus pruebas puras compatibles sí forman parte de la regresión.

Límite de la evidencia: ejecución headless/input simulado y layout 360×720 en PC.
No se probó render visual, APK, touch físico ni background/resume real de Android.
Importación cliente advierte Android build-tools ausente. Diario y recuperación
no persisten tras reiniciar SSS/cerrar cliente. No hay acreditación económica.

### Inventario del cambio frente a la base 2899abb

**55 archivos: 42 nuevos y 13 modificados; ninguno eliminado.** Incluye diseño
ya publicado y todos los archivos aún sin seguimiento; un diff --stat normal
no cuenta estos últimos. Los 19 .uid se agrupan con su script en la tabla.
Cifras aproximadas de líneas: alrededor de 3.500 añadidas y 55 retiradas;
documentación incluye los informes de todas las etapas.

| Archivo (incluye .uid nuevo cuando se indica) | + líneas aprox. | − líneas |
| --- | ---: | ---: |
| app/main.gd | 162 | 3 |
| app/main.tscn | 78 | 19 |
| config/client_connection_config.gd | 2 | 0 |
| config/default_client_connection.tres | 1 | 0 |
| contracts/sss_protocol_v1.md | 222 | 0 |
| docs/team3/TEAM3-M3-MINING-DESIGN.md | ~900 | 0 |
| docs/TESTING.md | 62 | 2 |
| modules/team3/mining/mining_intent_state.gd (+ .uid) | 210 | 0 |
| modules/team3/network/sss_connection.gd | 60 | 7 |
| modules/team3/world/world_debug_view.gd | 14 | 2 |
| server/sss/config/asteroid_config.gd (+ .uid) | 16 | 0 |
| server/sss/config/default_asteroid_config.tres | 11 | 0 |
| server/sss/config/default_mining_config.tres | 7 | 0 |
| server/sss/config/mining_config.gd (+ .uid) | 6 | 0 |
| server/sss/config/sss_config.gd | 2 | 1 |
| server/sss/mock/mock_world_seed.gd | 1 | 0 |
| server/sss/network/websocket_gateway.gd | 99 | 12 |
| server/sss/tests/asteroid_gateway_sync_test.gd (+ .uid) | 167 | 0 |
| server/sss/tests/asteroid_state_test.gd (+ .uid) | 50 | 0 |
| server/sss/tests/asteroid_world_sync_test.gd (+ .uid) | 96 | 0 |
| server/sss/tests/mining_gateway_test.gd (+ .uid) | 236 | 0 |
| server/sss/tests/mining_idempotency_test.gd (+ .uid) | 79 | 0 |
| server/sss/tests/mining_lifecycle_test.gd (+ .uid) | 81 | 0 |
| server/sss/tests/mining_scene_server.gd (+ .uid) | 44 | 0 |
| server/sss/tests/mining_validation_test.gd (+ .uid) | 75 | 0 |
| server/sss/world/asteroid_state.gd (+ .uid) | 87 | 0 |
| server/sss/world/entity_state.gd | 4 | 1 |
| server/sss/world/mining_operation.gd (+ .uid) | 63 | 0 |
| server/sss/world/mining_service.gd (+ .uid) | 205 | 0 |
| server/sss/world/solar_system_world.gd | 103 | 8 |
| tests/m3_asteroid_replica_test.gd (+ .uid) | 50 | 0 |
| tests/m3_mining_connection_test.gd (+ .uid) | 55 | 0 |
| tests/m3_mining_input_test.gd (+ .uid) | 60 | 0 |
| tests/m3_mining_intent_test.gd (+ .uid) | 66 | 0 |
| tests/m3_mining_scene_test.gd (+ .uid) | 148 | 0 |
| tools/run_m3_mining_smoke.ps1 | 27 | 0 |

No hay commit, push, merge ni PR de la implementación. El remoto de minería
conserva sólo el diseño 374c833; los cambios de código/pruebas y cierre son locales.

### Integración compartida: MERGE NO por ahora

Durante el cierre se hizo fetch de origin/integration/team3-m3. Avanzó desde
2899abb a **a18c195 — feat(team3): implement M3 combat vertical slice**. No se
cambió la base de trabajo ni se incorporó ese commit automáticamente.

Hay siete rutas modificadas en ambos trabajos:

- app/main.gd y app/main.tscn.
- contracts/sss_protocol_v1.md.
- modules/team3/network/sss_connection.gd.
- server/sss/mock/mock_world_seed.gd.
- server/sss/network/websocket_gateway.gd.
- server/sss/world/solar_system_world.gd.

Son solapamientos detectados mediante comparación de diffs, no conflictos de
merge ya resueltos. Combat usa una extensión attack/combat_result sobre M2;
esta rama negocia M2/M3 por sesión y configura la demo en M3. Combinarlo requiere
decidir soporte de Combat en M3, preservar sus mensajes/correlación y coordinar
pending entre viaje, ataque e inicio/parada de minería. También falta decidir
qué ocurre con minería activa al atacar; no se inventa esa regla en el cierre.

**Recomendación: MERGE NO contra la integración actual.** La vertical slice
minera sobre 2899abb pasa sus pruebas y está lista para revisión; su combinación
con a18c195 aún no está validada. La siguiente tarea, tras coordinación, debe
preservar ambos slices, integrar los siete archivos compartidos y ejecutar juntas
las regresiones de Travel/Nave, minería y Combat, incluidos sus E2E. Sólo después
corresponde reevaluar MERGE SÍ y preparar publicación/PR según autorización.

Se detiene aquí conforme al cierre por etapas del documento de prompts. No se
implementaron combate/economía nuevos ni se avanzó a otra etapa por iniciativa propia.
