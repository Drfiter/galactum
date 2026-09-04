# Contrato WebSocket Cliente ↔ SSS

Este archivo es compartido entre el desarrollador del cliente (Godot Android) y
el desarrollador del SSS (Godot headless). No debe modificarse silenciosamente.

- `team3-m0.1`: contrato diagnóstico de TEAM3-M0 (shipped, estable). El SSS y el
  cliente actuales hablan esta versión en runtime.
- `team3-m1.0`: acuerdo de integración TEAM3-M1 (documentado a continuación).

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
