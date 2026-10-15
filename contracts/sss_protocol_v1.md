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
