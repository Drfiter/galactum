# TEAM3-M3 — Combat M3 v1

Estado: ETAPA FINAL. Vertical slice funcional nave contra nave preparado para revisión.

Este documento separa deliberadamente reglas encontradas en las fuentes de
Galactum, decisiones temporales de M3, decisiones todavía abiertas y elementos
fuera del alcance. Nada marcado `PROVISIONAL M3` debe presentarse como
arquitectura, catálogo o balance definitivo.

## IMPLEMENTADO

El alcance entregado en esta rama es:

- combate nave contra nave;
- resolver determinista y sin azar;
- ataque autoritativo derivado de la sesión autenticada;
- correlación por `request_id` y resultado identificado por `combat_id`;
- idempotencia en memoria durante la vida del SSS;
- cliente y UI mínima para seleccionar, atacar y presentar el resultado;
- selección compartida mediante mouse y touch;
- integración completa cliente → WebSocket → SSS → resolver → cliente.

### Autoridad y seguridad

- El cliente envía intenciones; no calcula ni declara resultados autoritativos.
- El servidor deriva al atacante desde la identidad autenticada. El cliente no
  envía atacante, ownership, `player_id`, `ship_id`, unidades, daño, bajas ni
  outcome.
- `attack` exige una sesión autenticada antes de llegar a `CombatService`.
- Una nave `TRAVELING` no puede atacar ni ser atacada.
- El objetivo debe existir, ser una nave ajena `ANCHORED` y estar dentro del AOI
  autoritativo del jugador.
- La resolución de combate debe ser pura, determinista y versionada mediante
  `combat_version`.
- `entity_id`, `ship_id`, `player_id` y `combat_id` representan identidades
  diferentes y no son intercambiables.
- La arquitectura completa documentada asigna al SSS el contacto espacial y al
  SGM el resolver persistente integrado con inventario, tropas y Criosantuario.

Fuentes revisadas:

- `_ai_context/docs/equipo_3_mundo_y_combate_spec_de_desarrollo.md`
- `_ai_context/docs/plan_de_desarrollo_equipo_3.md`
- `_ai_context/docs/endpoints_equipo_3.md`
- `contracts/sss_protocol_v1.md`
- `docs/team3/OPEN_DECISIONS.md`

### Arquitectura final del corte

```text
ShipSelectionState + WorldState
  -> AttackIntentState
  -> SssConnection
  -> WebSocketGateway (autenticación y forma estricta)
  -> CombatService (autoridad, validación e idempotencia)
  -> CombatSnapshotProvider
  -> CombatResolverPort
  -> LocalCombatResolver
  -> CombatResolution
  -> combat_result
  -> CombatResultState (deduplicación)
  -> UI mínima
```

`CombatResolverPort` mantiene desacoplado el resolver local provisional. El
proveedor mock conserva fuerzas y aplica bajas sólo dentro de su propio estado;
no modifica `WorldState`, `EntityState`, economía, inventario ni progresión.

### Versiones

- `protocol_version: "team3-m2.0"` identifica el protocolo de transporte activo
  compartido con M2. La extensión Combat no cambia la semántica de
  `start_travel`.
- `combat_version: "m3-provisional-1"` identifica exclusivamente las reglas y
  el comportamiento del resolver provisional. No sustituye ni incrementa
  `protocol_version`.

### Determinismo comprobado

- Las mismas entradas y la misma configuración producen el mismo
  `CombatResolution`.
- Los stacks se copian y ordenan por `unit_type_id`; su orden de entrada no
  cambia el resultado.
- No se usa `RandomNumberGenerator`, seed ni otra fuente de azar.
- El `combat_id` se genera fuera del resolver y no participa en sus cálculos.
- Las bajas están acotadas por las unidades recibidas, las cantidades restantes
  nunca son negativas y se conserva `bajas + restantes = entrada`.

### Idempotencia comprobada

- `(player_id autenticado, request_id)` identifica una intención durante la
  vida del proceso SSS.
- Un retry con el mismo target devuelve el mismo resultado de negocio:
  `combat_id`, `combat_version`, participantes, outcome, bajas y fuerzas
  restantes.
- Reutilizar el mismo `request_id` con otro target devuelve
  `ATTACK_REQUEST_CONFLICT`.
- El resolver y la aplicación de bajas mock se ejecutan una sola vez.
- `seq` y `server_time` pertenecen al envelope de transporte y pueden cambiar
  entre respuestas sin cambiar el resultado de negocio.
- El cliente correlaciona por `request_id` y deduplica por `combat_id`.
- No existe persistencia de idempotencia después de reiniciar el SSS.

### Demo reproducible

Requisitos: Godot 4.6.2, dos terminales y el puerto `9100` disponible. Desde la
raíz del repositorio, iniciar primero el SSS:

```powershell
godot --headless --path .\server\sss
```

En otra terminal, iniciar el cliente:

```powershell
godot --path .
```

En el cliente:

1. Esperar la autenticación mock y el `full_snapshot`.
2. Seleccionar con mouse o touch la nave ajena visible.
3. Pulsar **Atacar**.
4. Comprobar el estado pendiente con su `request_id`.
5. El SSS valida sesión, atacante, objetivo, estados y AOI; genera `combat_id` y
   ejecuta el resolver determinista.
6. El cliente recibe `combat_result` y muestra outcome y resumen de bajas.

La prueba automatizada equivalente es:

```powershell
# Requiere un SSS ya iniciado en el puerto elegido.
godot --headless --path . --script res://tests/m3_combat_scene_test.gd -- --port=9100
```

## PROVISIONAL M3

- resolver local dentro del SSS;
- fórmula simple de daño simultáneo;
- unidades genéricas por `unit_type_id`;
- ataque directo nave contra nave sin flota funcional;
- extensión Combat sobre `protocol_version: "team3-m2.0"`.

### Ubicación y límite

**PROVISIONAL M3 - aprobado sólo para este corte.** Durante M3 el resolver puro
vive en `server/sss/combat/`. `CombatService` lo consume exclusivamente a
través de `CombatResolverPort`; `LocalCombatResolver` es el adaptador local que
podrá sustituirse por una integración SGM sin acoplar mundo, red o presentación.

La interfaz funcional de sustitución es:

```text
CombatResolverPort.resolve(attacker_snapshot, defender_snapshot, rules)
    -> CombatResolution
```

El resolver no conoce WebSocket, sesiones, AOI, Nodes, reloj, almacenamiento,
economía ni estado del mundo.

### Participantes y unidades

- El corte inicial será nave contra nave mientras no exista una implementación
  funcional de flotas.
- `CombatParticipantSnapshot` conserva `entity_id`, `ship_id`, `player_id`,
  `kind` y stacks genéricos.
- Cada stack contiene sólo `unit_type_id` y `quantity`.
- `CombatRules` contiene `combat_version` y definiciones configurables con
  `attack` y `durability` enteros positivos.
- `mock_unit_alpha` y `mock_unit_beta` son fixtures técnicos. No constituyen ni
  anticipan el catálogo oficial de tropas.

### Algoritmo técnico

1. Validar configuración, identificadores, tipos conocidos, stacks únicos y
   cantidades no negativas.
2. Copiar y ordenar los stacks por `unit_type_id` para obtener una entrada
   canónica sin mutar los snapshots recibidos.
3. Calcular para cada lado `attack_power = sum(quantity * attack)`.
4. Aplicar ambos daños simultáneamente sobre los stacks del rival en orden
   canónico. Sólo una unidad completa cuya `durability` sea cubierta cuenta
   como baja; el daño parcial restante no persiste después de esta resolución.
5. Comparar el poder de ataque restante y devolver `attacker_win`,
   `defender_win` o `draw`.

Este algoritmo demuestra determinismo, daño simultáneo, bajas y conservación
de unidades. No es balance definitivo. No usa `seed` porque no contiene azar.
Si posteriormente se introduce aleatoriedad, la seed deberá ser un input
explícito y parte de la información necesaria para reproducir el resultado.

### Resultado del núcleo

`CombatResolution` contiene:

- éxito o error de validación;
- `combat_version`;
- outcome;
- bajas por bando;
- fuerzas restantes por bando.

No contiene `request_id`, `combat_id`, timestamps ni efectos del mundo. En
ETAPA 3 `CombatService` agrega esos metadatos sin contaminar el resolver puro.

### Flujo autoritativo de ETAPA 3

La extensión provisional conserva `protocol_version: team3-m2.0`:

```text
attack
  -> WebSocketGateway valida autenticación y forma estricta
  -> CombatService deriva la nave desde player_id autenticado
  -> valida target, ownership, ANCHORED y AOI
  -> CombatSnapshotProvider entrega snapshots mock
  -> CombatResolverPort ejecuta el resolver local
  -> el proveedor aplica las bajas sólo a su estado mock
  -> CombatService registra request_id/combat_id y devuelve combat_result
```

La idempotencia usa `(player_id, request_id)` durante la vida del proceso. Un
retry exacto reutiliza el resultado y `combat_id`; cambiar el target con la
misma clave devuelve `ATTACK_REQUEST_CONFLICT`. Ni `EntityState` ni la réplica
del mundo reciben bajas o efectos de derrota.

### Cliente mínimo de ETAPA 4

El cliente reutiliza `ShipSelectionState`, `WorldState` y el hit-testing único
de `WorldDebugView`. Una nave ajena visible seleccionada se convierte en el
`target_entity_id`; la nave propia sólo se consulta localmente para habilitar
la acción y jamás se envía como atacante.

```text
selección mouse/touch
  -> AttackIntentState valida disponibilidad local provisional
  -> SssConnection genera request_id y envía attack mínimo
  -> SSS autentica, deriva atacante y resuelve
  -> combat_result
  -> CombatResultState deduplica por combat_id
  -> UI muestra outcome y resumen de bajas
```

`AttackIntentState` conserva como máximo una solicitud pendiente. Si el
objetivo sale del AOI antes del envío, deja de ser atacable; si sale después,
se mantiene sólo la correlación hasta que el SSS responda. Los rechazos de
Combat se correlacionan por `request_type: attack` y no resuelven una intención
de Travel.

`CombatResultState` almacena copias de los datos de presentación y deduplica el
resultado de negocio por `combat_id`. No compara byte a byte el sobre de red:
un reenvío puede tener otro `seq` o `server_time` sin volver a aplicar ni mostrar
el mismo combate. No muta `WorldState`, inventario, economía ni progresión.

Al desconectar, reconectar o reanudar la aplicación se descarta cualquier
pendiente local no reconstruible. No se reenvía automáticamente ni se inventa
un resultado. La recuperación histórica queda explícitamente pendiente para
ETAPA 5.

## PENDIENTE DE DECISIÓN

- Versión definitiva del protocolo posterior a la extensión provisional sobre
  `team3-m2.0`.
- Forma contractual final posterior a M3 de `attack`, `combat_started` y
  `battle_report`.
- Ubicación definitiva e integración del resolver real en SGM.
- Modelo funcional de flotas y contacto mediante viaje.
- Catálogo canónico de tropas, tiers, matriz de ventajas, formaciones, rondas,
  escudos y reglas completas de bajas.
- Persistencia de idempotencia y resultados después de reiniciar el SSS.
- Replay/consulta histórica de resultados al reconectar (ETAPA 5).
- Integración posterior con PvE/Xenoforms cuando la rama World/PvE esté
  terminada e integrada.
- Alcance o distancia de ataque de gameplay.
- Efectos mundiales posteriores a una derrota.

## FUERA DE ALCANCE

Combat M3 v1 no incluye:

- migración global a `team3-m3.0`;
- replay de resultados al reconectar;
- economía, inventario, progresión o datos reales del Equipo 2;
- monetización;
- destrucción o retirada de naves;
- loot, recompensas, Bahía Médica o Criosantuario;
- comportamiento PvE, Xenoforms, minería o World/PvE;
- seeds, azar o persistencia entre reinicios.

## Evidencia

Las pruebas del resolver cubren casos canónicos, simultaneidad, orden canónico,
ausencia de mutación, configuración inválida, participantes inválidos,
determinismo y conservación exhaustiva de unidades para rangos pequeños.

Las pruebas de ETAPA 3 cubren autenticación previa, forma estricta de `attack`,
derivación autoritativa del atacante, ownership, estados de viaje, AOI,
snapshots, idempotencia, aplicación única y separación de errores Combat/Travel.

Las pruebas del cierre cubren intención local, selección compartida mouse/touch,
payload mínimo, IDs únicos, una sola solicitud pendiente, salida de AOI,
separación de errores, deduplicación por `combat_id`, limpieza de reconexión y
el recorrido real cliente → WebSocket → SSS → resolver → UI.
