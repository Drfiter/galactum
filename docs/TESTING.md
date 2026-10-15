# Pruebas de Galactum

## Estado de esta matriz

Verificación de cierre de minería: **2026-10-14, Windows, Godot 4.6.2.stable.official.71f334935**, rama `feature/team3-m3-mining`, HEAD `374c833` más cambios locales de ETAPAS 2–5 sobre base `2899abb`. Pasaron 34 pruebas distintas en 35 ejecuciones: 32 de lógica/protocolo, una escena de minería y una escena de nave ejecutada en M2 y M3. Cada ejecución terminó con código 0 y su marcador OK.

La evidencia anterior registra el cierre minero sobre esa base. La solución actual también incorpora Combat de `a18c195`: la revisión conjunta aprobó **44 pruebas distintas / 46 ejecuciones**, incluida cancelación minera de ambos participantes al aceptarse combate. Ver [informe de convivencia](team3/TEAM3-M3-MINING-COMBAT-REVIEW.md). Los smoke M0/M1 siguen siendo históricos y no se ejecutaron.

En los comandos, `godot` representa el ejecutable de Godot 4.6.2. En Windows puede reemplazarse por la ruta completa del `.exe`.

## Matriz de pruebas

| Prueba | Proyecto | Comando | Qué valida | Resultado esperado | Hito |
| --- | --- | --- | --- | --- | --- |
| `m0_protocol_smoke.gd` | Cliente + SSS | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_m0_smoke.ps1 -GodotPath "C:\ruta\Godot_v4.6.2-stable_win64.exe"` | Flujo E2E histórico de autenticación, snapshot y pong M0. | `M0_SMOKE_OK` | M0 |
| `world_snapshot_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/world_snapshot_test.gd` | Snapshot base, mapa 600 x 600, IDs y entidad inicial. | `SSS_WORLD_TEST_OK` | M0 |
| `m1_client_world_state_test.gd` | Cliente | `godot --headless --path . --script res://tests/m1_client_world_state_test.gd` | `full_snapshot`, `map_delta`, merge de `updated`, `removed`, limpieza y secuencias no consecutivas entre deltas. | `M1_CLIENT_WORLD_STATE_TEST_OK` | M1 |
| `m1_sss_connection_sequence_test.gd` | Cliente | `godot --headless --path . --script res://tests/m1_sss_connection_sequence_test.gd` | Continuidad de `seq`, detección de desync y nueva base mediante snapshot completo. | `M1_SSS_CONNECTION_SEQUENCE_TEST_OK` | M1 |
| `m1_protocol_smoke.gd` | Cliente + SSS | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_m1_smoke.ps1 -GodotPath "C:\ruta\Godot_v4.6.2-stable_win64.exe"` | Flujo E2E histórico M1 con múltiples entidades, snapshot y pong. | `M1_SMOKE_OK` | M1 |
| `entity_registry_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/entity_registry_test.gd` | Alta, consulta, actualización, eliminación y orden estable del registro de entidades. | `ENTITY_REGISTRY_TEST_OK` | M1 |
| `spatial_hash_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/spatial_hash_test.gd` | Inserción, consulta por celda, movimiento, eliminación y tamaño de celda del índice espacial. | `SPATIAL_HASH_TEST_OK` | M1 |
| `aoi_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/aoi_test.gd` | Inclusión y exclusión de entidades por AOI y configuración independiente del índice espacial. | `AOI_TEST_OK` | M1 |
| `world_snapshot_multi_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/world_snapshot_multi_test.gd` | Snapshot completo con múltiples entidades y filtrado por AOI. | `WORLD_SNAPSHOT_MULTI_TEST_OK` | M1 |
| `world_delta_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/world_delta_test.gd` | Ciclo del changeset y transiciones `added`, `updated` y `removed` según AOI. | `WORLD_DELTA_TEST_OK` | M1 |
| `changeset_lifecycle_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/changeset_lifecycle_test.gd` | Orden de runtime `tick`, publicación de deltas y confirmación de cambios. | `CHANGESET_LIFECYCLE_TEST_OK` | M1 |
| `m2_sss_connection_test.gd` | Cliente | `godot --headless --path . --script res://tests/m2_sss_connection_test.gd` | Payload de `start_travel`, una solicitud pendiente y separación entre error del servidor y error de protocolo. | `M2_SSS_CONNECTION_TEST_OK` | M2 |
| `m2_travel_intent_test.gd` | Cliente | `godot --headless --path . --script res://tests/m2_travel_intent_test.gd` | Selección de nave propia, destino provisional, cancelación, confirmación y rechazo de intención. | `M2_TRAVEL_INTENT_TEST_OK` | M2 |
| `m2_travel_projection_test.gd` | Cliente | `godot --headless --path . --script res://tests/m2_travel_projection_test.gd` | Interpolación, ETA, objeto `travel`, llegada, búsqueda de nave propia y snapshot durante viaje. | `M2_TRAVEL_PROJECTION_TEST_OK` | M2 |
| `m2_world_debug_view_test.gd` | Cliente | `godot --headless --path . --script res://tests/m2_world_debug_view_test.gd` | Selección con mouse y destino mediante entrada táctil sobre la vista del mundo. | `M2_WORLD_DEBUG_VIEW_TEST_OK` | M2 |
| `travel_math_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/travel_math_test.gd` | Matemática pura de duración, progreso, posición y tiempos de viaje. | `TRAVEL_MATH_TEST_OK` | M2 |
| `travel_start_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/travel_start_test.gd` | Inicio autoritativo de viaje y errores para solicitudes inválidas. | `TRAVEL_START_TEST_OK` | M2 |
| `travel_snapshot_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/travel_snapshot_test.gd` | Snapshot completo de una nave `TRAVELING` con estado y datos de viaje. | `TRAVEL_SNAPSHOT_TEST_OK` | M2 |
| `travel_delta_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/travel_delta_test.gd` | Forma de los deltas de inicio, progreso y llegada del viaje. | `TRAVEL_DELTA_TEST_OK` | M2 |
| `travel_tick_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/travel_tick_test.gd` | Posición derivada por timestamps, actualización a 2 Hz y llegada exacta. | `TRAVEL_TICK_TEST_OK` | M2 |
| `travel_aoi_test.gd` | SSS | `godot --headless --path .\server\sss --script res://tests/travel_aoi_test.gd` | Transiciones de AOI por sesión para una nave en movimiento. | `TRAVEL_AOI_TEST_OK` | M2 |

## Compatibilidad de los smoke tests históricos

Los runners `run_m0_smoke.ps1` y `run_m1_smoke.ps1` esperan versiones de protocolo históricas. En esta rama el cliente demo usa `team3-m3.0` y el SSS acepta M2/M3 por sesión; esos runners no deben presentarse como smoke tests ejecutables sobre el runtime actual hasta que el equipo defina una estrategia de compatibilidad o los actualice.

Esta limitación no cambia que M0 y M1 sean hitos completados; indica que sus harnesses E2E quedaron ligados a sus versiones históricas.

## Ejecución manual

Las pruebas puras del cliente y del SSS pueden ejecutarse individualmente con los comandos de la tabla. Las pruebas E2E requieren un runner que controle el ciclo de vida del SSS y use una versión de protocolo compatible.

Antes de registrar un resultado como evidencia CAPSTONE se recomienda guardar:

- commit y rama probados;
- versión exacta de Godot;
- comando ejecutado;
- salida con el marcador esperado;
- plataforma usada;
- fecha de ejecución.

## Matriz M3 verificada

Las filas siguientes también dieron OK en el cierre. Las pruebas de gateway abren
sus propios servidores; no requieren iniciar otro SSS. No existe un umbral de
cobertura porcentual establecido: la evidencia cubre los comportamientos indicados.

| Prueba | Proyecto | Qué valida | Marcador obtenido |
| --- | --- | --- | --- |
| `m3_ship_representation_test.gd` | Cliente | Selección visual, estado y proyección de nave | `M3_SHIP_REPRESENTATION_TEST_OK` |
| `m3_ship_selection_test.gd` | Cliente | Selección única, ownership y desaparición | `M3_SHIP_SELECTION_TEST_OK` |
| `m3_ship_scene_test.gd` | Cliente + SSS | Escena de viaje, reconexión y llegada; ejecutada en M2/M3 | `M3_SHIP_SCENE_TEST_OK` |
| `asteroid_state_test.gd` | SSS | Configuración independiente, cantidad, ocupación y agotamiento | `ASTEROID_STATE_TEST_OK` |
| `asteroid_world_sync_test.gd` | SSS | Snapshot/delta, cambios y entradas/salidas de AOI | `ASTEROID_WORLD_SYNC_TEST_OK` |
| `asteroid_gateway_sync_test.gd` | SSS | Dos sesiones WebSocket, secuencias y formato M2/M3 | `ASTEROID_GATEWAY_SYNC_TEST_OK` |
| `m3_asteroid_replica_test.gd` | Cliente | Réplica de asteroides, merge y removed | `M3_ASTEROID_REPLICA_TEST_OK` |
| `mining_lifecycle_test.gd` | SSS | Inicio, extracción temporal, cancelación y agotamiento | `MINING_LIFECYCLE_TEST_OK` |
| `mining_validation_test.gd` | SSS | Ownership, rango, sistema, estado y exclusividad | `MINING_VALIDATION_TEST_OK` |
| `mining_idempotency_test.gd` | SSS | Replay, conflicto, stop antiguo, reloj y límite del diario | `MINING_IDEMPOTENCY_TEST_OK` |
| `mining_gateway_test.gd` | SSS | Payload mínimo, autoridad, correlación y replay por WebSocket | `MINING_GATEWAY_TEST_OK` |
| `m3_mining_intent_test.gd` | Cliente | Intención, recuperación y resultado deduplicado | `M3_MINING_INTENT_TEST_OK` |
| `m3_mining_connection_test.gd` | Cliente | Versión, pending común, errores y desync | `M3_MINING_CONNECTION_TEST_OK` |
| `m3_mining_input_test.gd` | Cliente | Mouse/touch, asteroide superpuesto y convivencia con Travel | `M3_MINING_INPUT_TEST_OK` |
| `m3_mining_scene_test.gd` | Cliente + SSS | Demo E2E: viaje, rango, reconexión, parada, agotamiento y desync | `M3_MINING_SCENE_TEST_OK` |

Para pruebas individuales, sustituir `<prueba>` por el nombre de la tabla:

```powershell
# Importar ambos proyectos antes de ejecutar scripts:
godot --headless --editor --path . --import
godot --headless --editor --path server/sss --import
# Cliente:
godot --headless --path . --script res://tests/<prueba>.gd
# SSS:
godot --headless --path server/sss --script res://tests/<prueba>.gd
# E2E minería: el runner inicia y cierra su propio SSS de prueba.
powershell.exe -NoProfile -File tools/run_m3_mining_smoke.ps1 -GodotPath C:/ruta/a/godot.exe -Port 19325
```

Para la escena de nave, iniciar un SSS nuevo en otro terminal con
`godot --headless --path server/sss -- --port=19323`; ejecutar
`godot --headless --path . --script res://tests/m3_ship_scene_test.gd -- --port=19323 --protocol=team3-m2.0`.
Repetir con SSS nuevo y `--protocol=team3-m3.0`. El cierre empleó un helper temporal
que automatiza ese mismo ciclo, sin versionar rutas específicas de esta máquina.

La fixture de minería acelera sólo Travel a 600 unidades/minuto; producción
conserva 10. Se comprobó parada con cantidad 1 y agotamiento posterior con 9,
sin duplicar resultados al reconectar. El test de registro emite errores
intencionales para duplicado/inexistente y concluye con `ENTITY_REGISTRY_TEST_OK`.

Importaciones terminaron con código 0. El editor del cliente informa que falta
Android build-tools: no se generó APK ni se probó en dispositivo. Input touch y
layout 360×720 se verificaron de forma simulada/headless; no equivalen a validación
visual ni a background/resume real de Android. Persistencia y economía quedan fuera.

Informe de alcance, inventario y recomendación de integración:
[TEAM3-M3-MINING-DESIGN.md](team3/TEAM3-M3-MINING-DESIGN.md#15-informe-de-cierre--etapa-5).
