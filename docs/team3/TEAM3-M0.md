# TEAM3-M0 — Base cliente/SSS

## Resultado esperado

M0 valida el riesgo tecnico minimo de Equipo 3:

`Cliente Godot -> WebSocket JSON -> SSS Godot headless local -> autenticacion mock -> full snapshot -> nave dummy visible`

El SSS mantiene el reloj y el estado real del mundo a 2 ticks/s. El cliente solo solicita, recibe y representa. No existe movimiento ni simulacion de gameplay en M0.

## Proyectos

- Cliente: raiz de este repositorio (`project.godot`).
- SSS headless: `server/sss/project.godot`.
- Contrato M0: `contracts/sss_protocol_v1.md`.
- Decisiones aun no resueltas: `docs/team3/OPEN_DECISIONS.md`.

No hay Autoloads, Event Bus ni Service Locator. `app/main.gd` compone la conexion, el modelo recibido y la vista. El SSS compone configuracion, autenticador mock, mundo en memoria y gateway WebSocket.

## Requisitos

- Godot 4.6 con ejecutable accesible.
- Puerto TCP 9100 libre (o elegir otro en ambos procesos).

## 1. Levantar primero el SSS

Desde la raiz del repositorio:

```powershell
godot --headless --path .\server\sss
```

Para otro puerto:

```powershell
godot --headless --path .\server\sss -- --port=9200
```

El proceso debe imprimir una linea semejante a:

```text
SSS_READY protocol=team3-m0.1 port=9100 tick_hz=2.0 system_id=...
```

## 2. Levantar despues el cliente

En otra terminal:

```powershell
godot --path .
```

Por defecto intentara `ws://127.0.0.1:9100`. Host y puerto se pueden cambiar en la vista diagnostica y luego pulsar **Conectar**.

## Comprobacion manual

Una ejecucion correcta muestra:

1. `autenticacion mock aceptada` brevemente;
2. `full_snapshot recibido`;
3. `protocol=team3-m0.1`, `seq` y `server_time` en pantalla;
4. `player_id`, `ship_id`, `entity_id` y `system_id` separados;
5. un marcador celeste de la nave dummy en el centro del mapa diagnostico 600x600;
6. luego, latencia de ping/pong.

## Pruebas automatizadas

Prueba pura del snapshot del SSS:

```powershell
godot --headless --path .\server\sss --script res://tests/world_snapshot_test.gd
```

Smoke test completo (el script levanta y detiene el SSS):

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tools\run_m0_smoke.ps1 -GodotPath "C:\ruta\a\godot.exe"
```

El resultado exitoso incluye `SSS_WORLD_TEST_OK` o `M0_SMOKE_OK`, respectivamente.

## Android en la misma red

1. Conecta PC y dispositivo Android a la misma LAN.
2. Inicia el SSS en el PC y permite conexiones entrantes al puerto elegido en el firewall, solo para la red privada si corresponde.
3. Obtiene la IPv4 LAN del PC (por ejemplo con `ipconfig`).
4. Exporta/instala el preset Android de diagnostico. El SDK y keystore se configuran en Godot localmente; no se versionan rutas, claves ni passwords.
5. En el cliente Android reemplaza `127.0.0.1` por la IPv4 del PC y pulsa **Conectar**. `127.0.0.1` desde Android apunta al telefono, no al PC.
6. Comprueba los mismos textos y marcador de la seccion anterior.

M0 usa `ws://` en una LAN de desarrollo. Una integracion desplegada debe definir seguridad, `wss://`, autenticacion real y recuperacion de sesion con Equipo 1. La orientacion, 2D/3D y renderer definitivo siguen abiertos.

## Alcance deliberadamente excluido

Movimiento (`start_travel`/`move_fleet`), asteroides, mineria, PvE, combate, Redis, economia, JWT/JWKS real, SGM real, integraciones reales con Equipos 1/2, pathfinding, sistema completo de entidades y arte final.
