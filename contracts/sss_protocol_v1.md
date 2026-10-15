# Contrato WebSocket Cliente ↔ SSS

Este archivo es compartido entre el desarrollador del cliente (Godot Android) y
el desarrollador del SSS (Godot headless). No debe modificarse silenciosamente.

- `team3-m0.1`: contrato diagnóstico histórico de TEAM3-M0 (shipped, estable).
- `team3-m1.0`: contrato runtime actual de TEAM3-M1 (documentado a continuación).

---

# Contrato TEAM3-M0 (`team3-m0.1`)

Estado: contrato diagnóstico de M0. No es un protocolo de producción.

## Transporte y formato

- WebSocket sin TLS (`ws://`) para desarrollo local y LAN.
- Un objeto JSON por mensaje.
- El cliente incluye `protocol_version` en cada mensaje.
- El SSS incluye `protocol_version`, `seq` y `server_time` en cada respuesta.
- `protocol_version`: `team3-m0.1`.
- `seq`: entero creciente por conexión, comenzando en 1.
- `server_time`: tiempo Unix del SSS en milisegundos.

## Cliente a SSS

### Autenticación mock

```json
{"type":"auth","protocol_version":"team3-m0.1","jwt":"team3-m0-local-player"}
```

`jwt` es solamente el token mock consumido por M0. No representa el contrato
futuro de Equipo 1.

### Solicitud de snapshot completo

```json
{"type":"full_snapshot","protocol_version":"team3-m0.1"}
```

### Ping diagnóstico opcional

```json
{"type":"ping","protocol_version":"team3-m0.1","client_time":1234}
```

## SSS a cliente

### Autenticación aceptada

```json
{
  "type":"auth_ok",
  "protocol_version":"team3-m0.1",
  "seq":1,
  "server_time":1780000000000,
  "auth_mode":"mock",
  "player_id":"018f0000-0000-7000-8000-000000000001",
  "system_id":"018f0000-0000-7000-8000-000000000003"
}
```

### Snapshot completo

```json
{
  "type":"map_delta",
  "protocol_version":"team3-m0.1",
  "seq":2,
  "server_time":1780000000000,
  "full":true,
  "system_id":"018f0000-0000-7000-8000-000000000003",
  "map_size":[600,600],
  "added":[{
    "kind":"ship",
    "entity_id":"018f0000-0000-7000-8000-000000000004",
    "ship_id":"018f0000-0000-7000-8000-000000000002",
    "player_id":"018f0000-0000-7000-8000-000000000001",
    "system_id":"018f0000-0000-7000-8000-000000000003",
    "display_name":"M0 Dummy",
    "position":[300,300]
  }],
  "updated":[],
  "removed":[]
}
```

### Pong y error

`pong` devuelve el `client_time` recibido. `error` devuelve `error_code` y
`message`; ambos conservan el sobre común.

## Fuera de M0

No hay movimiento, deltas periódicos, persistencia, Redis, JWT/JWKS,
autorización de producción, rate limiting, reanudación de sesión ni garantías
de entrega.

---

# Acuerdo de integración TEAM3-M1 (`team3-m1.0`)

Acuerdo definido junto con el desarrollador del SSS. La implementación del
cliente de M1 se rige por este sobre y estos mensajes.

## Versión de protocolo

`protocol_version`: `team3-m1.0`

## Mensaje único de mundo: `map_delta`

Se mantiene un único mensaje de mundo, `map_delta`, para snapshot completo e
incrementos.

### Snapshot completo

```json
{
  "type": "map_delta",
  "protocol_version": "team3-m1.0",
  "seq": <int>,
  "server_time": <int>,
  "full": true,
  "system_id": "...",
  "map_size": [600,600],
  "added": [...],
  "updated": [],
  "removed": []
}
```

### Delta incremental

```json
{
  "type": "map_delta",
  "protocol_version": "team3-m1.0",
  "seq": <int>,
  "server_time": <int>,
  "full": false,
  "system_id": "...",
  "added": [...],
  "updated": [...],
  "removed": ["entity_id", ...]
}
```

## Forma mínima de una entidad serializada

```json
{
  "entity_id": "...",
  "kind": "ship|fleet|asteroid|xenoform",
  "position": [x,y]
}
```

Puede contener campos adicionales específicos del tipo cuando sean necesarios,
pero M1 no debe inventar gameplay para ellos.

- `added` contiene entidades completas.
- `updated` contiene como mínimo `entity_id` y únicamente los campos
  actualizados cuando sea apropiado.
- `removed` contiene únicamente `entity_id`.

## Semántica de `seq`

- `seq` es monotónico por conexión y pertenece a TODOS los mensajes enviados
  por el SSS, no solamente a `map_delta`.
- La validación de continuidad de `seq` se realiza en el cliente
  (`SssConnection`), porque recibe `auth_ok`, `map_delta`, `pong`, `error`, etc.
- El cliente (`WorldState`) NO exige que dos `map_delta` tengan `seq`
  consecutivo: solo registra el `seq` del último estado aplicado.
- Si el cliente detecta un gap real de `seq`:
  - marca desincronización;
  - solicita `full_snapshot`;
  - el próximo snapshot completo reconstruye `WorldState`.
- Al crear una conexión nueva se reinicia el seguimiento de `seq`.

No se necesitan ACKs, retransmisión propia ni reliable messaging adicional.

## Área de Interés (AOI)

- El SSS calcula el Área de Interés usando el estado autoritativo del jugador.
- No se implementa `subscribe_area` en M1.
- No se envía `aoi_radius_cells` al cliente en M1.
- El cliente solamente acepta que una entidad puede:
  - aparecer mediante `added`;
  - cambiar mediante `updated`;
  - desaparecer mediante `removed`.
- `removed` significa: "esta entidad ya no pertenece a la réplica visible del
  cliente". No debe interpretarse necesariamente como destrucción de la entidad.

## Fuera de M1

Movimiento (`start_travel`, `move_fleet`), `depart_ts`, `arrive_ts`, ETA, rutas,
interpolación real de flotas y movimiento autoritativo corresponden a TEAM3-M2.

---

# Acuerdo de integración TEAM3-M2-I (`team3-m2.0`)

TEAM3-M2-I añade el viaje básico de la Astronave sobre las garantías de M1. El
cliente selecciona, solicita y representa; el SSS conserva autoridad sobre
aceptación, estado, posición y tiempos.

## Versión y sobre

- `protocol_version`: `team3-m2.0`.
- Todo mensaje SSS → cliente conserva `protocol_version`, `seq` monotónico por
  conexión y `server_time` Unix en milisegundos.
- Snapshot completo e incrementos continúan usando exclusivamente `map_delta`.

## Intención cliente → SSS: `start_travel`

```json
{
  "type": "start_travel",
  "protocol_version": "team3-m2.0",
  "destination": [420, 180]
}
```

- `destination` contiene dos coordenadas enteras del mapa.
- No se envían `entity_id`, `player_id`, origen, posición, estado ni ETA.
- El SSS identifica la nave mediante el `player_id` autenticado.
- Solo puede existir una intención `start_travel` pendiente por cliente. Mientras
  espera resolución, el cliente deshabilita Confirmar/Viajar.
- No existe mensaje `travel_started`.

## Confirmación autoritativa de inicio

La aceptación se confirma únicamente mediante un `map_delta` que cambia la nave
propia a `TRAVELING`:

```json
{
  "type": "map_delta",
  "protocol_version": "team3-m2.0",
  "seq": 3,
  "server_time": 1780000000000,
  "full": false,
  "system_id": "...",
  "added": [],
  "updated": [{
    "entity_id": "...",
    "kind": "ship",
    "state": "TRAVELING",
    "position": [300, 300],
    "travel": {
      "origin": [300, 300],
      "destination": [420, 180],
      "depart_ts": 1780000000000,
      "arrive_ts": 1780000060000
    }
  }],
  "removed": []
}
```

`depart_ts` y `arrive_ts` son enteros Unix en milisegundos. Los updates de
`position` del SSS a 2 Hz siguen siendo estado autoritativo para AOI y
sincronización. La vista usa `travel` para movimiento suave sin escribir la
posición interpolada en la réplica.

Un `full_snapshot` recibido durante un viaje incluye la misma representación
completa `state: TRAVELING` + `travel`, permitiendo reconstruir ruta y ETA tras
reconexión.

## Llegada

El SSS determina la llegada y publica mediante `map_delta`:

```json
{
  "entity_id": "...",
  "state": "ANCHORED",
  "position": [420, 180],
  "travel": null
}
```

`travel: null` reemplaza el objeto anidado completo y evita campos obsoletos con
el merge superficial de `WorldState`.

## Rechazos del SSS

Un rechazo usa el mensaje `error` existente y no constituye un error de
protocolo. Códigos acordados:

- `INVALID_REQUEST`
- `INVALID_DESTINATION`
- `SHIP_NOT_FOUND`
- `SHIP_NOT_ANCHORED`

El cliente mantiene separadas las señales de error de protocolo y error del
servidor.

## Interpolación y ETA

El cliente estima `server_now` usando el último `server_time` recibido más el
tiempo monotónico local transcurrido. No usa el reloj Unix local como autoridad.

La posición visual se deriva de `origin`, `destination`, `depart_ts` y
`arrive_ts`, con progreso limitado a `[0, 1]`. Esa posición no modifica
`WorldState.position`.

## Fuera de TEAM3-M2-I

Reserva de destino, persistencia, recovery del SSS por timestamps, Redis,
costos/economía, cooldown, minería y combate corresponden a etapas posteriores.

---

# Extensión TEAM3-M3-MINING (`team3-m3.0`)

Implementada en ETAPA 3 de `feature/team3-m3-mining` siguiendo el diseño revisado
y la autorización del usuario para continuar esa etapa. Las reglas de minería
siguientes son **PROVISIONAL M3** de demostración, no balance oficial del producto.
Fuente y decisiones pendientes: `docs/team3/TEAM3-M3-MINING-DESIGN.md`.
El acuerdo M2 anterior permanece válido y conserva su serialización.

## Versiones por sesión

- SSS admite `team3-m2.0` y `team3-m3.0` explícitamente.
- Autenticación mock usa el mensaje `auth` existente con la versión elegida.
- Tras autenticar, la versión queda fija para esa conexión. Cambiarla devuelve
  `ERR_PROTOCOL_VERSION` usando el sobre de la sesión ya autenticada.
- Todas las respuestas conservan `protocol_version`, `seq` continuo por conexión
  y `server_time` Unix en milisegundos, incluidos errores y replays.
- Snapshots/deltas continúan usando `map_delta`. El gateway espera el primer
  snapshot antes de emitir incrementos a esa sesión.
- Una sesión M2 conserva campos anteriores, sin bloques/campos nuevos de minería;
  intentar minería en M2 devuelve `ERR_UNKNOWN_MESSAGE`. No se añade negociación
  genérica de capacidades ni retransmisión de transporte.

## Asteroide visible M3

`added` y snapshot completo incluyen identidad, posición y configuración visible:

```json
{
  "entity_id": "asteroid-id",
  "kind": "asteroid",
  "position": [310, 290],
  "state": "ANCHORED",
  "system_id": "system-id",
  "asteroid_type": "demo_asteroid",
  "resource_type": "demo_ore",
  "remaining_quantity": 10,
  "asteroid_state": "AVAILABLE",
  "occupant_entity_id": null
}
```

`state` heredado no representa el ciclo de minería ni vuelve móvil al asteroide.
`asteroid_state` puede ser `AVAILABLE`, `OCCUPIED` o `DEPLETED`. El ocupante es el
`entity_id` de la nave, nullable; no es un ID enviado como autoridad por cliente.
Updates incluyen `entity_id`, posición/estado heredados, cantidad restante,
`asteroid_state` y ocupante; no requieren repetir configuración estática.

## Intención de inicio

```json
{
  "type": "start_mining",
  "protocol_version": "team3-m3.0",
  "request_id": "00000000-0000-4000-8000-000000000001",
  "asteroid_entity_id": "asteroid-id"
}
```

Sólo esos campos están permitidos. `request_id` es UUID textual de 36 caracteres
en grupos 8-4-4-4-12 hexadecimales; se normaliza a minúsculas para correlación y
diario. `asteroid_entity_id` es un String no vacío de una entidad existente.
No aceptar player_id, actor entity_id, posiciones, tasas, cantidades o recompensas
aportados por el cliente. SSS deriva la nave del jugador autenticado, como M2.

Validaciones: autenticación, nave propia existente, tipo asteroide, mismo sistema,
nave `ANCHORED`, rango euclídeo inclusivo, depósito no agotado, un proceso por
nave y ocupación exclusiva del asteroide. Validación/adquisición son atómicas.
No se admite iniciar mientras `TRAVELING` ni viajar automáticamente al objetivo.

## Intención de parada

```json
{
  "type": "stop_mining",
  "protocol_version": "team3-m3.0",
  "mining_id": "uuid-asignado-por-sss"
}
```

Sólo esos campos están permitidos. SSS asigna `mining_id` al iniciar; únicamente
su propietario puede detenerlo. Una parada de un ID viejo nunca detiene otro
proceso activo. Parar liquida unidades enteras hasta ese instante, descarta la
fracción final y libera ocupación. Si al liquidar se agota, termina COMPLETED;
en otro caso termina CANCELLED con motivo USER_CANCELLED.

## Confirmación, progreso y resultado

Inicio/parada nuevos se confirman por `map_delta`, sin `mining_started`.
Naves M3 incluyen `mining` y `last_mining_result`, objetos completos o null.
El cliente usa merge superficial: esos bloques sustituyen al anterior entero.

```json
{
  "entity_id": "ship-entity-id",
  "state": "ANCHORED",
  "mining": {
    "mining_id": "uuid-asignado-por-sss",
    "request_id": "00000000-0000-4000-8000-000000000001",
    "asteroid_entity_id": "asteroid-id",
    "status": "ACTIVE",
    "resource_type": "demo_ore",
    "rate_units_per_second": 1,
    "started_ts": 1780000000000,
    "updated_ts": 1780000002500,
    "extracted_quantity": 2
  },
  "last_mining_result": null
}
```

La extracción usa tiempo SSS acumulado en ms: floor(tasa * elapsed_ms / 1000),
descontando lo ya contabilizado y limitándolo al restante. Fracciones sobreviven
entre ticks; timestamps repetidos/retroceso del reloj no duplican extracción.

```json
{
  "entity_id": "ship-entity-id",
  "mining": null,
  "last_mining_result": {
    "mining_id": "uuid-asignado-por-sss",
    "request_id": "00000000-0000-4000-8000-000000000001",
    "asteroid_entity_id": "asteroid-id",
    "status": "COMPLETED",
    "reason": "DEPLETED",
    "resource_type": "demo_ore",
    "quantity": 10,
    "finished_ts": 1780000010000
  }
}
```

Estados terminales: COMPLETED/DEPLETED o CANCELLED con motivo USER_CANCELLED,
TRAVEL_STARTED o INVALIDATED. La finalización es única y el resultado es una
copia estable, sin acreditación de economía/inventario/progresión.
Iniciar otra operación conserva el último resultado hasta terminar la siguiente.
Snapshot reconstruye operación activa y último resultado sin depender de eventos.

Agotamiento conserva asteroide DEPLETED visible con restante 0; no hay respawn.
Desconexión no cancela y reconexión recupera mediante snapshot. La nave conserva
ANCHORED/TRAVELING; minería es independiente del estado de movimiento.
Viaje válido liquida y cancela minería antes de iniciar TRAVELING; un viaje
rechazado conserva minería. Si se agota al liquidar, prevalece COMPLETED/DEPLETED.
Invalidez de actor/objetivo/propiedad/sistema/estado/rango cancela sin extraer fuera
de condiciones. El diario permite recuperar resultado aunque desaparezca el actor.

## Reintentos e idempotencia

Clave `(player_id, request_id)` ligada al objetivo. Mismo inicio devuelve la
decisión original; objetivo distinto devuelve MINING_REQUEST_CONFLICT. Rechazos
de negocio autenticados y bien formados también se conservan: reevaluar condiciones
requiere un request_id nuevo. No registrar paquetes malformados o sin autenticación.

Reintento de operación activa republica la nave actual por map_delta. Una terminal
se recupera mediante mensaje `mining_replay`, además de republicar estado actual:

```json
{
  "type": "mining_replay",
  "protocol_version": "team3-m3.0",
  "seq": 12,
  "server_time": 1780000015000,
  "request_type": "start_mining",
  "request_id": "00000000-0000-4000-8000-000000000001",
  "mining_id": "uuid-asignado-por-sss",
  "result": {
    "mining_id": "uuid-asignado-por-sss",
    "request_id": "00000000-0000-4000-8000-000000000001",
    "asteroid_entity_id": "asteroid-id",
    "status": "COMPLETED",
    "reason": "DEPLETED",
    "resource_type": "demo_ore",
    "quantity": 10,
    "finished_ts": 1780000010000
  }
}
```

Para stop repetido, request_type es stop_mining, se correlaciona por mining_id
y no incluye request_id de parada. result conserva request_id del inicio original.
Replay no sobrescribe operación/resultado actuales del mundo ni acredita otra vez.
Cliente debe deduplicar avisos por mining_id y resolver sólo intención coincidente.

Diario efímero limitado a 256 intenciones por jugador en configuración demo.
No expulsa claves; lleno rechaza nuevos inicios con MINING_LIMIT_REACHED.
Paradas/replays siguen permitidos. No hay garantía tras reiniciar SSS.

## Errores de minería

Mensaje error existente con error_code, message, request_type y, si son Strings,
request_id normalizado y/o mining_id de la solicitud. No reutilizar códigos Travel
para resolver minería; estos rechazos no son errores de protocolo:

- MINING_INVALID_REQUEST
- MINING_NOT_AUTHENTICATED
- MINING_SHIP_NOT_FOUND
- MINING_SHIP_NOT_ANCHORED
- MINING_ASTEROID_NOT_FOUND
- MINING_SYSTEM_MISMATCH
- MINING_OUT_OF_RANGE
- MINING_ALREADY_ACTIVE
- MINING_DEPLETED
- MINING_ASTEROID_OCCUPIED
- MINING_OPERATION_NOT_FOUND
- MINING_NOT_OWNER
- MINING_REQUEST_CONFLICT
- MINING_LIMIT_REACHED

## AOI y límites de la demo

SSS compara AOI con visible_ids de cada sesión para added/updated/removed,
incluidos asteroides inmóviles cuando se mueve el observador. removed significa
salida de réplica, no destrucción ni cancelación. Snapshots reinician visibilidad.
Todas las sesiones leen el mismo ChangeSet antes de que el runtime lo limpie.

Valores PROVISIONAL M3 centralizados: 10 unidades demo_ore, tasa 1 unidad/s,
rango 1 unidad. No son catálogo/balance oficial. Fuera: economía real, capacidad,
costos, cooldowns, producción de backend, Redis/persistencia y reglas de combate.
Cliente/UX de minería incorporados en ETAPA 4: configuración de demo usa M3.
La opción cliente `--protocol=team3-m2.0` conserva una ruta de regresión M2.

---

# Extensión provisional TEAM3-M3 Combat sobre `team3-m2.0`

Esta extensión añade ataque autoritativo nave contra nave sin cambiar la
versión global ni modificar la semántica de `start_travel`. No representa el
contrato definitivo de flotas o combate de Galactum.

`protocol_version: "team3-m2.0"` versiona el transporte actualmente aceptado
por cliente y SSS. `combat_version` versiona exclusivamente el resolver y sus
reglas; no modifica ni reemplaza `protocol_version`.

## Intención cliente → SSS: `attack`

```json
{
  "type": "attack",
  "protocol_version": "team3-m2.0",
  "request_id": "client-generated-request-id",
  "target_entity_id": "target-world-entity-id"
}
```

Son los únicos cuatro campos aceptados. La presencia de campos adicionales se
rechaza con `INVALID_ATTACK_REQUEST`. En particular, el cliente no envía ni
controla atacante, `player_id`, `ship_id`, unidades, daño u outcome.

El SSS procesa `attack` sólo después de autenticar la sesión. Deriva la nave
atacante desde el `player_id` autenticado y usa `target_entity_id` únicamente
para resolver el objetivo visible en el mundo autoritativo.

## Resultado SSS → cliente: `combat_result`

```json
{
  "type": "combat_result",
  "protocol_version": "team3-m2.0",
  "seq": 4,
  "server_time": 1780000000000,
  "request_id": "client-generated-request-id",
  "combat_id": "combat-server-generated-id",
  "combat_version": "m3-provisional-1",
  "resolved_ts": 1780000000000,
  "attacker": {
    "entity_id": "attacker-world-entity-id",
    "ship_id": "attacker-ship-id"
  },
  "defender": {
    "entity_id": "target-world-entity-id",
    "ship_id": "target-ship-id"
  },
  "outcome": "attacker_win|defender_win|draw",
  "casualties": {
    "attacker": [{"unit_type_id": "mock_unit_alpha", "quantity": 1}],
    "defender": []
  },
  "remaining_forces": {
    "attacker": [{"unit_type_id": "mock_unit_alpha", "quantity": 2}],
    "defender": [{"unit_type_id": "mock_unit_beta", "quantity": 1}]
  }
}
```

`combat_id` lo genera el SSS. Los nombres `mock_unit_alpha` y
`mock_unit_beta` son datos técnicos provisionales, no un catálogo oficial.
Las bajas sólo afectan al estado mock de Combat y no modifican entidades del
mundo, economía, inventario o progresión.

## Idempotencia

- La clave en memoria es `(player_id autenticado, request_id)`.
- Repetir la misma solicitud con el mismo target devuelve el mismo cuerpo de
  resultado y `combat_id`, sin resolver ni aplicar bajas otra vez.
- `seq` y `server_time` pertenecen al sobre de la conexión actual y continúan
  avanzando aunque el cuerpo sea un replay idempotente.
- Reutilizar `request_id` con otro target devuelve
  `ATTACK_REQUEST_CONFLICT`.
- No existe persistencia de esta garantía después de reiniciar el SSS.

## Validaciones y errores de Combat

- `ERR_NOT_AUTHENTICATED`
- `INVALID_ATTACK_REQUEST`
- `ATTACKER_NOT_FOUND`
- `TARGET_NOT_FOUND`
- `UNSUPPORTED_ATTACKER_KIND`
- `UNSUPPORTED_TARGET_KIND`
- `CANNOT_ATTACK_SELF`
- `CANNOT_ATTACK_OWN_SHIP`
- `ATTACKER_NOT_ANCHORED`
- `TARGET_NOT_ANCHORED`
- `TARGET_NOT_VISIBLE`
- `COMBAT_DATA_UNAVAILABLE`
- `INVALID_COMBAT_CONFIGURATION`
- `COMBAT_ID_GENERATION_FAILED`
- `COMBAT_RESULT_APPLY_FAILED`
- `ATTACK_REQUEST_CONFLICT`
- `COMBAT_UNAVAILABLE`

Los errores de esta extensión incluyen `request_type: "attack"` y, cuando el
valor recibido permite correlación, `request_id`. Esto los mantiene separados
de los rechazos de Travel.

## Fuera de esta extensión

No se incluyen flotas funcionales, rango de gameplay, destrucción o retirada
de naves, loot, economía, progresión, Criosantuario, recompensas, PvE,
Xenoforms ni persistencia entre reinicios. La UI no forma parte del contrato
wire; el cliente mínimo de la vertical slice se documenta en
`docs/team3/TEAM3-M3-COMBAT-DESIGN.md`.

## Convivencia Mining/Combat aprobada el 2026-10-14

Combat acepta attack/combat_result bajo M2 y M3 y conserva la versión negociada
en cada respuesta. Su cuerpo, combat_version e idempotencia no cambian.
Minería sigue disponible sólo en M3. El cliente mantiene una sola intención de
red pendiente entre viaje, ataque e inicio/parada minera; combate ya resuelto y
minería activa no son solicitudes pendientes.

Un combate nuevo aceptado cancela minería activa de atacante y defensor, liquida
la extracción transcurrida y publica resultado CANCELLED con reason COMBAT_STARTED
mediante map_delta M3. Ataques rechazados y replay de un combate anterior no
interrumpen minería nueva. La cancelación no acredita inventario/economía ni
modifica el resolver puro; procede después de aplicar exitosamente el resultado
mock de combate y antes de publicar combat_result.
