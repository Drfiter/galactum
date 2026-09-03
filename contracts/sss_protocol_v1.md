# Contrato WebSocket TEAM3-M0

Estado: contrato diagnostico de M0. No es un protocolo de produccion.

## Transporte y formato

- WebSocket sin TLS (`ws://`) para desarrollo local y LAN.
- Un objeto JSON por mensaje.
- El cliente incluye `protocol_version` en cada mensaje.
- El SSS incluye `protocol_version`, `seq` y `server_time` en cada respuesta.
- `protocol_version`: `team3-m0.1`.
- `seq`: entero creciente por conexion, comenzando en 1.
- `server_time`: tiempo Unix del SSS en milisegundos.

## Cliente a SSS

### Autenticacion mock

```json
{"type":"auth","protocol_version":"team3-m0.1","jwt":"team3-m0-local-player"}
```

`jwt` es solamente el token mock consumido por M0. No representa el contrato futuro de Equipo 1.

### Solicitud de snapshot completo

```json
{"type":"full_snapshot","protocol_version":"team3-m0.1"}
```

### Ping diagnostico opcional

```json
{"type":"ping","protocol_version":"team3-m0.1","client_time":1234}
```

## SSS a cliente

### Autenticacion aceptada

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

`pong` devuelve el `client_time` recibido. `error` devuelve `error_code` y `message`; ambos conservan el sobre comun.

## Fuera de M0

No hay movimiento, deltas periodicos, persistencia, Redis, JWT/JWKS, autorizacion de produccion, rate limiting, reanudacion de sesion ni garantias de entrega.
