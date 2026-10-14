# Arquitectura de Galactum

## Alcance

Este documento describe la arquitectura implementada en el repositorio para el estado activo M2. M0 y M1 constituyen la base histórica ya integrada.

## Vista general

```text
Entrada del jugador
       |
       v
Cliente Godot
       |
       | WebSocket con objetos JSON
       v
SSS Godot headless
       |
       v
Mundo autoritativo en memoria
```

El cliente y el SSS son proyectos Godot separados dentro del mismo repositorio:

- El cliente usa el `project.godot` de la raíz.
- El SSS usa `server/sss/project.godot`.
- `server/.gdignore` impide que el proyecto cliente importe el proyecto anidado del servidor.

La configuración predeterminada usa el puerto `9100`, un mapa de pruebas de `600 x 600` y el protocolo `team3-m2.0`.

## Cliente Godot

El cliente es responsable de:

- abrir y mantener la conexión WebSocket;
- autenticar mediante el proveedor mock actual;
- validar la continuidad de los mensajes del SSS;
- mantener una réplica local mediante `WorldState`;
- presentar las entidades recibidas;
- procesar selección, paneo, zoom y entrada táctil o de mouse;
- enviar intenciones, como `start_travel`, sin apropiarse de la autoridad del mundo;
- proyectar visualmente un viaje a partir de los tiempos autoritativos recibidos.

La escena principal compone la conexión, el estado del mundo, la vista y el estado transitorio de la intención de viaje. No se usa un Autoload para estas responsabilidades.

## SSS headless

El Servidor de Sistema Solar es un proyecto Godot ejecutado sin interfaz gráfica. Mantiene:

- las sesiones WebSocket;
- la autenticación mock desacoplada mediante un autenticador;
- el registro de entidades;
- el índice espacial y el Área de Interés, o AOI;
- el reloj y los ticks de simulación;
- el estado autoritativo de la nave y sus viajes;
- los cambios pendientes que se publican como deltas.

El SSS se ejecuta de forma predeterminada a 2 ticks por segundo. La configuración está separada en un `Resource` que puede duplicarse y recibir un puerto alternativo en tiempo de ejecución.

## Autoridad del servidor

El SSS decide el estado válido del mundo. En M2 esto implica que:

- el cliente solicita un viaje mediante un destino;
- el cliente no envía como autoridad su posición, origen, ETA, `player_id` o `entity_id`;
- el SSS identifica la nave del jugador autenticado;
- el SSS valida el destino y el estado de la nave;
- el SSS establece `ANCHORED` o `TRAVELING`, la posición y los tiempos del viaje;
- la aceptación se confirma mediante un `map_delta`, no mediante una confirmación local del cliente;
- la llegada también se publica mediante el estado autoritativo.

La posición interpolada por el cliente es solo presentación. No reemplaza la posición guardada en `WorldState`.

## Transporte WebSocket JSON

Cliente y servidor intercambian un objeto JSON por mensaje. El sobre de los mensajes enviados por el SSS contiene:

- `protocol_version`;
- `seq`;
- `server_time`.

La versión activa es `team3-m2.0`. El contrato detallado se conserva en `contracts/sss_protocol_v1.md`.

## WorldState

`WorldState` es la réplica local del mundo visible para el cliente. Mantiene, entre otros datos:

- `protocol_version`;
- último `seq` aplicado al estado;
- `server_time` y una estimación monotónica del tiempo actual del SSS;
- `system_id`;
- tamaño del mapa;
- entidades indexadas por `entity_id`.

`WorldState` no es la autoridad del juego. Su función es reconstruir y consultar el estado que el SSS publica.

## Snapshot completo

El cliente solicita `full_snapshot` después de autenticarse y cuando necesita reconstruir su réplica.

El SSS responde con un mensaje `map_delta` que incluye `full: true`. El cliente reemplaza el contenido previo de `WorldState` con los datos del snapshot. En M2, un snapshot recibido durante un viaje puede incluir el estado `TRAVELING` y el objeto `travel`, lo que permite reconstruir la trayectoria visual y la ETA.

## Deltas de mapa

Los cambios incrementales también usan `map_delta`, pero con `full: false`.

Cada delta puede contener:

- `added`: entidades completas que entran en la réplica visible;
- `updated`: cambios de entidades que ya forman parte de la réplica;
- `removed`: identificadores que dejan de pertenecer a la réplica visible.

`removed` no implica necesariamente que una entidad haya sido destruida. También puede significar que salió del AOI del jugador.

## Secuencias y recuperación de desincronización

El campo `seq` es monotónico por conexión y se aplica a todos los mensajes del SSS, no solo a los deltas de mundo.

`SssConnection` valida la continuidad porque es el componente que recibe `auth_ok`, `map_delta`, `pong`, `error` y los demás tipos. `WorldState` registra el último `seq` aplicado, pero no exige que dos `map_delta` sean consecutivos porque otros mensajes pueden intercalarse.

El flujo de recuperación es:

```text
SssConnection detecta un salto de seq
                |
                v
emite desync_detected y no aplica el mensaje incremental
                |
                v
envía request_full_snapshot
                |
                v
el SSS responde con map_delta full=true
                |
                v
WorldState se reconstruye y la secuencia establece una nueva base
```

Al abrir una conexión nueva se reinicia el seguimiento de secuencia.

## Separación entre lógica y presentación

- `WorldState` contiene la réplica de datos.
- `SssConnection` contiene transporte y validación del sobre.
- `WorldDebugView` dibuja y procesa la interacción sobre el mapa.
- `TravelIntentState` mantiene selección y confirmación transitorias del cliente.
- `TravelProjection` calcula posición visual y ETA sin mutar el estado autoritativo.
- El SSS mantiene simulación, AOI, entidades y cambios del mundo.

Esta separación permite reemplazar posteriormente autenticación mock o fuentes externas sin reescribir la lógica principal del mundo.
