# TEAM3-M3 — Diseño propuesto de Asteroides y Minería

## Estado, fuentes y clasificación

ETAPA 1: diseño pendiente de aprobación; minería no implementada.
Rama: feature/team3-m3-mining. Base verificada: 2899abb, coincidente con la
referencia origin/integration/team3-m3. Tras habilitar permisos, se verificó
también en GitHub que ambas ramas apuntaban a 2899abb el 2026-10-14.
Este documento no autoriza las etapas siguientes ni modifica el contrato compartido.

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
nave observadora sin added/removed. No validado por prueba nueva todavía.
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
El usuario autorizó incorporar y subir este documento de diseño; esa autorización
no aprueba reglas provisionales ni permite avanzar a la implementación.
