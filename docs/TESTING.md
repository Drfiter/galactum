# Pruebas de Galactum

## Estado de esta matriz

Esta tabla se obtuvo de los archivos de prueba versionados. **Las pruebas no fueron ejecutadas durante la preparación de esta documentación**, por lo que los valores de “resultado esperado” describen el marcador que cada prueba imprime cuando termina correctamente, no una validación realizada en esta actualización.

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

Los runners `run_m0_smoke.ps1` y `run_m1_smoke.ps1` esperan versiones de protocolo históricas. El cliente y el SSS activos usan `team3-m2.0`, por lo que esos runners no deben presentarse como smoke tests ejecutables sobre el runtime M2 actual hasta que el equipo defina una estrategia de compatibilidad o los actualice.

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
