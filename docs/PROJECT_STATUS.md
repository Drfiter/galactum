# Estado del proyecto Galactum

## Estado oficial

El estado activo del repositorio es **M2**.

```text
M0 -> infraestructura base
M1 -> sincronización e interacción de mundo
M2 -> viaje autoritativo de la nave
```

M0 y M1 son hitos históricos completados e integrados. La rama y el protocolo M2 representan el desarrollo actual.

## M0 completado

M0 estableció la infraestructura mínima entre los dos proyectos Godot:

- conexión Cliente Godot con SSS headless;
- transporte WebSocket;
- objetos JSON;
- `protocol_version`;
- `seq` creciente por conexión;
- `server_time` entregado por el SSS;
- autenticación mock;
- snapshot inicial;
- ping y pong;
- una nave de diagnóstico dentro del mapa 600 x 600.

M0 se conserva como antecedente. Su versión de protocolo y sus smoke tests no corresponden al runtime M2 activo.

## M1 completado e integrado

M1 amplió la infraestructura para sincronizar un mundo con múltiples entidades:

- `WorldState` como réplica local del cliente;
- snapshot completo mediante `map_delta` con `full: true`;
- deltas incrementales mediante `map_delta` con `full: false`;
- operaciones `added`, `updated` y `removed`;
- registro de entidades e índice espacial en el SSS;
- Área de Interés calculada por el SSS;
- validación de secuencias sobre todos los mensajes del servidor;
- detección de saltos de secuencia;
- señal de desincronización;
- solicitud de `full_snapshot` para recuperación;
- nueva base de secuencia después del snapshot completo;
- selección de entidades por click o tap;
- paneo y zoom del mapa;
- culling de la vista;
- marcadores diferenciados por `kind`;
- preparación para reconexión y resume en Android.

M1 está integrado en el estado actual. Sus documentos y protocolos anteriores deben leerse como trazabilidad histórica cuando usen `team3-m1.0`.

## M2 activo

M2 añade el viaje básico de la nave sobre la infraestructura autoritativa de M1.

### Cliente

El código actual incluye:

- protocolo activo `team3-m2.0`;
- selección de la nave perteneciente al jugador autenticado;
- selección de un destino provisional con mouse o touch;
- confirmación y cancelación local del destino;
- una única solicitud `start_travel` pendiente;
- envío del destino sin enviar como autoridad `entity_id`, `player_id`, origen o ETA;
- separación entre errores de protocolo y rechazos del SSS;
- limpieza del estado transitorio al desconectarse o reanudarse la aplicación;
- recepción del estado `TRAVELING` como confirmación autoritativa;
- proyección visual entre origen y destino;
- cálculo de ETA a partir de `server_time` y tiempo monotónico local;
- reconstrucción de la trayectoria desde un snapshot completo;
- representación del destino provisional y del viaje en la vista del mundo.

### SSS

El código actual incluye:

- recepción de `start_travel`;
- identificación de la nave mediante el jugador autenticado;
- validación de la forma del destino;
- validación de límites del mapa;
- errores para solicitud inválida, destino inválido, nave inexistente o nave no anclada;
- estados `ANCHORED` y `TRAVELING`;
- datos de viaje con origen, destino, salida y llegada;
- velocidad de viaje configurable;
- avance autoritativo basado en timestamps;
- materialización de posición durante los ticks del SSS;
- publicación del inicio, progreso y llegada mediante `map_delta`;
- snapshot completo de una nave que ya está viajando;
- transiciones de AOI para entidades en movimiento;
- llegada exacta al destino y limpieza del objeto `travel`.

### Cobertura existente

El repositorio contiene pruebas unitarias o de integración para intención de viaje, conexión M2, proyección, interacción de la vista, matemática del viaje, inicio, snapshot, deltas, ticks y AOI. Su inventario está en [TESTING.md](TESTING.md).

La existencia de esos archivos no se registra aquí como una ejecución reciente.

## Funcionalidades posteriores

No se presentan como implementadas en el estado M2 actual:

- minería completa;
- enemigos y PvE completos;
- combate determinista completo;
- economía o progresión;
- persistencia de producción;
- autenticación real;
- integraciones finales con otros equipos.

Estas capacidades requieren hitos posteriores y decisiones todavía abiertas.

## Deuda documental conocida

Los siguientes elementos se mantienen sin cambios en esta preparación y deberán alinearse posteriormente con M2:

- introducción general y referencias a “runtime actual” en `contracts/sss_protocol_v1.md`;
- `tools/run_m1_smoke.ps1`;
- smoke tests M0 y su forma de ejecutarse contra versiones históricas;
- nombres y versión del preset en `export_presets.cfg`;
- guía histórica `docs/team3/TEAM3-M1-ANDROID.md`.
