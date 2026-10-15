# Revisión de integración: minería y combate M3

Estado: solución implementada y probada; el usuario autorizó expresamente commit,
push y merge hacia integration/team3-m3. Fecha: 2026-10-14.

La descripción de la copia y la rama original que sigue registra el estado al
terminar la revisión. La publicación autorizada traslada la solución validada a
feature/team3-m3-mining conservando la historia de Combat; los cambios originales
anteriores quedan respaldados en un stash identificado. No se publica en main.

## Ubicación y base

La rama de trabajo original sigue siendo feature/team3-m3-mining, HEAD 374c833,
con minería sobre base 2899abb. Se preservaron sus cambios locales.

La copia independiente se creó desde origin/integration/team3-m3 a18c195 mediante
git worktree, con HEAD separado. Se aplicaron los cambios mineros y se resolvieron
cinco archivos con conflictos textuales:

- app/main.gd y app/main.tscn.
- modules/team3/network/sss_connection.gd.
- server/sss/network/websocket_gateway.gd.
- contracts/sss_protocol_v1.md.

MockWorldSeed y SolarSystemWorld tenían solapamientos pero se combinaron sin
conflictos textuales. La copia conserva los servicios, resolver, UI y pruebas de
Combat existentes. La ubicación final y el parche se registran al pie.

## Decisión del usuario y comportamiento

El usuario eligió explícitamente: **cancelar la minería al participar en combate**.

Después de aceptar y aplicar exitosamente un combate nuevo, el SSS liquida la
extracción transcurrida y cancela minería activa de atacante y defensor. Publica
CANCELLED / COMBAT_STARTED con cantidad e IDs originales; libera los asteroides.
Si el depósito se agotó exactamente al liquidar el tiempo, conserva el resultado
COMPLETED / DEPLETED en lugar de finalizarlo dos veces.

Ataques rechazados, errores de resolver/proveedor, conflictos de request_id y
replay de un combate anterior no cancelan minería. El replay tampoco cancela
una operación minera iniciada después de ese combate. El resolver puro sigue
sin conocer minería; la orquestación se realiza entre CombatService y mundo.

Combat acepta su payload existente en M2 y M3. Cada respuesta conserva la versión
negociada de su conexión. Minería permanece sólo en M3; M2 conserva su forma
de snapshot y mensajes de viaje. combat_version y fórmula de combate no cambian.

El cliente mantiene una sola solicitud de red pendiente entre viaje, ataque,
inicio y parada minera. Una operación minera activa no equivale a solicitud
pendiente: permite seleccionar nave ajena y atacar, con posterior cancelación
autoritativa. Desconexión/desync descarta intención de ataque no reconstruible;
minería conserva su recuperación explícita existente.

## Cambios adicionales para la convivencia

Además de resolver los archivos compartidos:

- MiningService centraliza cancelación por actor con motivos de viaje/combate.
- SolarSystemWorld coordina la interrupción de ambos participantes y el reloj.
- CombatService solicita esa interrupción sólo para un combate nuevo exitoso.
- La escena conserva scroll, controles de 48 px y selección compartida.
- La fixture minera incluye Combat real, con Travel acelerado sólo para pruebas.
- El runner minero admite -SceneTest m3_mining_combat_scene_test.
- Se agregan mining_combat_integration_test y m3_mining_combat_scene_test.
- m3_combat_connection_test comprueba pending común y versión M3. Su fixture
  establece snapshot disponible; las pruebas de aislamiento inyectan solicitudes
  antiguas deliberadamente, porque la API ya impide crearlas simultáneamente.

## Evidencia

Windows, Godot 4.6.2.stable.official.71f334935. La validación final consta de
**44 pruebas distintas / 46 ejecuciones**:

| Grupo | Distintas | Ejecuciones | Resultado |
| --- | ---: | ---: | --- |
| Cliente: M1/M2/Nave/Selección/Asteroides/Minería/Combat | 15 | 15 | Todos los marcadores OK |
| SSS: mundo, AOI, Travel, asteroides, minería y Combat | 24 | 24 | Todos los marcadores OK |
| mining_combat_integration_test | 1 | 1 | MINING_COMBAT_INTEGRATION_TEST_OK |
| m3_ship_scene_test, M2 y M3 | 1 | 2 | M3_SHIP_SCENE_TEST_OK |
| m3_combat_scene_test, M2 y M3 | 1 | 2 | M3_COMBAT_SCENE_TEST_OK |
| m3_mining_scene_test | 1 | 1 | M3_MINING_SCENE_TEST_OK |
| m3_mining_combat_scene_test | 1 | 1 | M3_MINING_COMBAT_SCENE_TEST_OK |

Cada ejecución final terminó con código 0. La prueba nueva de servidor comprueba
dos mineros, liquidación temporal, liberación, delta/AOI de ambos, M2 sin campos
mineros, rechazos/configuración inválida, replay/conflicto y stop antiguo.
La escena conjunta valida viaje, progreso, ataque, bloqueo de otras intenciones,
ambos resultados en UI y deduplicación después de reconectar.

No se presenta esta evidencia como APK ni prueba física Android. Continúa el
aviso de build-tools ausente. Las dos emisiones push_error del test de registro
son sus casos negativos esperados. Smoke M0/M1 históricos no se ejecutaron.

## Cómo reproducir en la copia de revisión

Desde la raíz de esa copia, con godot apuntando a Godot 4.6.2:

~~~powershell
godot --headless --editor --path . --import
godot --headless --editor --path server/sss --import
godot --headless --path server/sss --script res://tests/mining_combat_integration_test.gd
powershell.exe -NoProfile -File tools/run_m3_mining_smoke.ps1 -GodotPath C:/ruta/a/godot.exe -Port 19325 -SceneTest m3_mining_combat_scene_test
~~~

La demo normal utiliza dos terminales: godot --headless --path server/sss y
godot --path . Seleccionar nave propia, viajar a (310,290), elegir asteroide,
minar; luego seleccionar nave ajena visible y Atacar. Observar resultado de
combate y cancelación minera parcial. El viaje normal demora unos 85 segundos;
el runner acelera sólo ese trayecto. Para repetir, iniciar un SSS nuevo.

## Recomendación y siguiente acción

**La solución combinada está lista para revisión técnica.** Las pruebas resuelven
el impedimento técnico detectado al cierre, para la copia que contiene ambos
módulos. La rama original todavía no contiene esta integración y no debe
presentarse como equivalente ni publicarse como si ya la incluyera.

Antes de cambiar su base, conservar todo su trabajo, revisar el parche combinado
contra a18c195 y trasladar la solución validada preservando la historia de Combat.
Después corresponde commit + push desde la feature y PR hacia
integration/team3-m3, nunca main, conforme al documento de prompts. No se ejecutó
ninguna de esas operaciones de publicación ni un merge de ramas en esta revisión.

## Artefactos locales de revisión

- Copia completa: C:/Users/juani/OneDrive/Documentos/GitHub/galactum-m3-review
- Parche contra a18c195: C:/Users/juani/OneDrive/Documentos/GitHub/galactum-m3-review.patch
- Los cambios de la copia están preparados en su índice para revisar con
  git diff --cached; HEAD permanece separado en a18c195 y no se creó un commit.
- Comprobación de formato: git diff --cached --check, sin errores.
- El proyecto original galactum sólo recibe este informe y su enlace desde el
  diseño; no se trasladó allí código de la copia ni se cambió su rama.
