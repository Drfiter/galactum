# Diseño M3 Mundo PvE y Xenoforms

Estado: ETAPA 2 (SSS), ETAPA 4 (selección/inspección mínima), ETAPA 5
(política estática explícita y verificable) y ETAPA 6 (consulta SSS para Combat)
implementadas.
Representación cliente específica de ETAPA 3 y Combat no se implementan por inferencia.
Rama: `feature/team3-m3-world-pve`.
Base revisada: `2899abb3db75f102f69fa6cc6afafe13c7413293`, coincidente con la
referencia local `origin/integration/team3-m3`. Fecha: 2026-10-14.

El objetivo es un vertical slice completo: el SSS crea un Xenoform, lo registra
en el mundo y el índice espacial, publica snapshot/delta según AOI, el cliente
lo representa y selecciona, y Combat consulta sus datos sin depender de escenas.
No basta con agregar un marcador. Las secciones 1-15 conservan el diseño de referencia;
las secciones 16-19 registran exactamente lo implementado y probado en cada etapa.

## Clasificación y fuentes

- **REGLA OFICIAL**: instrucción explícita del usuario, reglas de AGENTS.md o
  garantías acordadas del contrato. No significa que el diseño nuevo ya esté aprobado.
- **PROVISIONAL M3 - requiere aprobación**: propuesta de esta rama, incluidos
  nombres de clases, campos de red, estados y comportamiento técnico mínimo.
- **PENDIENTE DE DECISIÓN**: falta una regla suficiente, existe contradicción
  o se necesita un acuerdo con otra rama/equipo.

| Fuente | Uso y clasificación |
| --- | --- |
| `AGENTS.md` | Reglas de alcance, separación, datos, Android y aprobación. |
| `contracts/sss_protocol_v1.md`, secciones M1 y M2 | Contrato vigente de réplica, AOI, secuencias y viaje. La introducción M1 es deuda documental. |
| `docs/team3/OPEN_DECISIONS.md` | Registro de contradicciones y decisiones no resueltas. |
| `docs/ARCHITECTURE.md`, `docs/PROJECT_STATUS.md`, `docs/TESTING.md` | Documentación de la implementación M2 y cobertura existente; no reglas nuevas de PvE. |
| `docs/team3/TEAM3-M3-SHIP-FLEET.md` y código Nave/Selección | Interfaz M3 actualmente implementada. |
| `lucas_mateo/1.5_GuiaEstudiante_Fase 1_Definicion Proyecto APT.docx` | Planificación general: spawning dinámico, PvE y futura configuración de Equipo 5; no detalla algoritmos ni valores canónicos. |
| Código y pruebas cliente/SSS en esta base | Implementación actual, no una fuente automática de gameplay. |

Las fuentes externas citadas por OPEN_DECISIONS.md bajo
`C:\Galactum\Galactum-20260828T023045Z-1-001\Galactum` no están disponibles en
esa ubicación. Los valores contradictorios se conocen por el registro, no por
una nueva lectura de los originales. No se copió código histórico ni de otras ramas.

## 1 Arquitectura

**REGLA OFICIAL**: SSS autoritativo, cliente como réplica/presentación, GDScript
tipado, sin economía, progresión, loot, tienda, monetización ni resolver completo.

**PROVISIONAL M3 - requiere aprobación**: reutilizar la infraestructura existente:

```text
Configuración XenoformConfig Resource
        |
        v
SolarSystemWorld.spawn_xenoform
        |
        v
XenoformState dentro de EntityRegistry + SpatialHash + WorldChangeSet
        |
        v
WebSocketGateway con visibilidad por conexión
        |
        v
map_delta full/incremental
        |
        v
SssConnection -> WorldState -> XenoformRepresentation
                                |
                                v
                     ShipSelectionState existente
                                |
                                v
                   WorldDebugView y UI diagnóstica
```

Combat consulta al SSS por ID y al cliente por la réplica para presentación.
No depende de WorldDebugView ni de una escena Xenoform. No se crea Autoload,
Event Bus global, Service Locator, segundo registro o segundo sistema de selección.

Alternativas consideradas:

| Alternativa | Evaluación |
| --- | --- |
| Sólo payload Dictionary y un marcador | Menor cambio, pero mantiene datos poco tipados y no ofrece una frontera suficiente para Combat. |
| XenoformConfig + especialización estrecha de EntityState + representación cliente | Recomendada: compatible con el registro y serializers actuales, con datos específicos separados. |
| Nuevo gestor PvE, registro, scheduler y selección propios | Descarta por duplicación y alcance prematuro. |

XenoformState se propone como subtipo estrecho de EntityState porque el registro
y el changeset ya trabajan con EntityState. Configuración y comportamiento se
componen; no se construye otra clase base universal ni una jerarquía de enemigos.

## 2 Modelo PvE y separación de datos

**PROVISIONAL M3 - requiere aprobación**:

| Dato | Configuración | Estado SSS | Réplica cliente |
| --- | --- | --- | --- |
| `entity_id` | No es identidad del catálogo | ID único recibido de un llamador interno del SSS | ID recibido, nunca nombre de Node |
| `kind` | No selecciona comportamiento arbitrario | Constante `xenoform` | Discriminador recibido |
| `config_id` | ID de definición técnica | Referencia a configuración validada | Campo recibido dentro del bloque xenoform |
| `system_id` | No procede del cliente | Sistema del mundo que registra la entidad | Dato recibido |
| `display_name` | Nombre visible | Copiado de configuración | Nombre recibido |
| `position` | La ubicación inicial pertenece al seed, no al catálogo | Vector2i autoritativo | Vector2 recibido, sin alterar precisión de red |
| `state` | Estado inicial definido por esta propuesta | IDLE para el slice estático | String recibido, sin decidir transiciones |
| `energy_cost` opcional | Valor configurable y presencia explícita | Sólo lectura para futura consulta de Combat | No se replica en esta propuesta |
| Vida/daño/debilidades/tropas | Sin catálogo suficiente para este alcance | No se implementan | No se inventan ni muestran barras |

La configuración Resource no guarda daño acumulado, objetivo, selección, posición
actual, timers o estado de una partida. La instancia autoritativa guarda su propio
estado; el cliente conserva únicamente copias provenientes de WorldState.

No se inventan `ship_id`, `fleet_id` o `player_id` para un Xenoform. `config_id`
identifica la definición y `entity_id` la instancia; varias instancias pueden
compartir configuración sin compartir estado mutable.

La vida no es necesaria para crear, replicar, seleccionar e identificar un objetivo.
Su unidad, valor inicial, daño y recuperación quedan fuera de este slice. Preparar
Combat significa poder consultar un objetivo válido y su definición, no inventar
los datos suficientes para ejecutar un combate completo.

## 3 Serialización y contrato propuesto

**REGLA OFICIAL**: conservar map_delta como único mensaje de mundo, sobre
protocol_version/seq/server_time, added completo, updated con entity_id y removed
con IDs. No cambiar start_travel ni sus errores o garantías.

**PROVISIONAL M3 - requiere aprobación y acuerdo de contrato**: esta forma completa
para un Xenoform creado por la nueva API. Los nombres y el estado no son oficiales:

```json
{
  "entity_id": "018f0000-0000-7000-8000-000000000009",
  "kind": "xenoform",
  "system_id": "018f0000-0000-7000-8000-000000000003",
  "position": [310, 315],
  "display_name": "Xenoform M3 de diagnóstico",
  "state": "IDLE",
  "xenoform": {
    "config_id": "m3-demo-static"
  }
}
```

ID y coordenadas del ejemplo reutilizan el fixture actual, no una regla de spawn.
El bloque xenoform pertenece a esta propuesta. config_id no fija un catálogo
oficial. No se envían Resources, rutas res://, NodePaths, energía privada o stats.

- Snapshot: entidad completa en added, full=true y updated/removed vacíos.
- Alta posterior al snapshot: entidad completa en added si entra en la visibilidad.
- Cambio de entidad ya conocida y visible: updated con entity_id, position, state
  y los campos específicos visibles completos cuando se serialice ese cambio.
- El bloque xenoform se reemplaza completo: el merge de WorldState es superficial,
  no un merge de campos anidados. No enviar parches incompletos dentro del bloque.
- Retirada: removed contiene el entity_id. No hay mensaje xenoform_spawned o ACK nuevo.
- Xenoform no publica travel. Los serializers de nave conservan travel y travel=null
  exactamente como M2. No se cambia el serializer genérico para inventar stats.

XenoformState tendría serializers específicos con una lista explícita de campos
visibles. No se serializa automáticamente todo el Resource o el payload interno.
Una actualización de datos específicos debe registrar el cambio antes del flush.

**PENDIENTE DE DECISIÓN**: documentar y aprobar campos/IDLE en
contracts/sss_protocol_v1.md antes de implementar. Se propone mantener team3-m2.0
como extensión de entidad que clientes genéricos toleran; esto necesita acuerdo
con Minería y Combat. No se declara compatibilidad con consumidores que validen
estrictamente otro esquema. Si el equipo exige nueva versión, debe cambiarse
coordinadamente cliente/SSS y pruebas. En esta etapa el contrato no se modifica.

## 4 Estados

**IMPLEMENTACIÓN ACTUAL, no regla PvE**: EntityState inicia toda entidad en
ANCHORED; el Xenoform Dummy hereda ese valor. ANCHORED/TRAVELING son la semántica
acordada del viaje de la nave, no un catálogo oficial de estados de enemigos.

**PROVISIONAL M3 - requiere aprobación**: un solo estado técnico IDLE para el
Xenoform inmóvil registrado. Significa reposo de esta demostración; no concede
permiso de atacar ni implica rango, hostilidad, vida o bloqueo de combate.

```text
Creación validada -> instancia registrada IDLE
Retirada explícita -> instancia ausente del registro
```

La retirada es un cambio de existencia, no un estado DEAD transmitido por inferencia.
Salir del AOI tampoco cambia el estado autoritativo. No se proponen PATROLLING,
CHASING, ATTACKING, IN_COMBAT o DEAD mientras falten reglas acordadas.

Los bucles de viaje no deben operar sobre Xenoforms. Nunca se asigna TRAVELING
a estas instancias. ANCHORED/TRAVELING y la aceptación del viaje propio permanecen
sin cambios para naves. Estado PvE final y transiciones de Combat quedan pendientes.

## 5 Configuración y creación

**PROVISIONAL M3 - requiere aprobación**: XenoformConfig Resource mínimo con
config_id y display_name. Para energía, has_energy_cost=false y energy_cost=0
como almacenamiento sin valor configurado; 0 con has_energy_cost=false nunca
significa costo gratuito. Si se configura un costo, debe ser un entero positivo.
La consulta de Combat devuelve null cuando no está configurado.

No hay una tabla oficial predeterminada ni se elige una de las tablas contradictorias.
El fixture m3-demo-static no configura energía. Pruebas de configuración pueden
usar valores artificiales explícitos para comprobar sustitución, sin convertirlos
en balance. El costo no se aplica, descuenta ni interpreta como vida.

API interna propuesta del SSS: spawn_xenoform(entity_id: String,
config: XenoformConfig, position: Vector2i) -> XenoformState o null.

Validar antes de alterar registro/índice/changeset: ID no vacío y no duplicado,
config_id/nombre no vacíos, configuración de energía válida y posición dentro del
mapa. Un rechazo no deja una entidad parcial. No se inventan reglas de colisión,
ocupación exclusiva, niveles, densidad o distancia a jugadores.

El llamador es exclusivamente código del SSS. No se abre un mensaje de red para
que el cliente genere enemigos o decida sus IDs. Se aceptan IDs provistos por el
seed/configuración interna; un generador persistente futuro no es necesario ahora.

La creación registra una única instancia en EntityRegistry/SpatialHash y una alta
en WorldChangeSet. El seed inicial usa la misma API; sus cambios de bootstrap se
limpian antes de aceptar sesiones para conservar el baseline de changeset vacío.
Las altas de runtime sí se publican en el siguiente flush.

La demo reemplaza el Xenoform Dummy actual con una instancia tipada conservando
su ID y posición técnica; no agrega una segunda copia. MockWorldSeed sólo configura
el fixture; no es el dueño del comportamiento PvE. Se propone copiar configuración
validada por instancia, sin mutar el Resource fuente ni mezclar estado de partida.

API interna complementaria: remove_xenoform(entity_id) -> bool, para retirar una
instancia de registro/índice y emitir el cambio. No implica matar, loot o respawn.
Retirar una entidad ausente no genera una segunda baja. No se reutiliza el ID para
una instancia diferente durante la misma ejecución.

## 6 AOI y removed

**REGLA OFICIAL**: AOI calculado por el SSS. removed significa que la entidad deja
la réplica visible; no permite concluir destrucción. ChangeSet no se drena por sesión.

**IMPLEMENTACIÓN ACTUAL**: SpatialHash consulta candidatos, luego el mundo filtra
por radio cuadrado configurado y posición autoritativa de la nave. Este diseño no
declara esa forma como regla definitiva de gameplay.

Limitación detectada por inspección: delta_for sólo recorre las entidades del
changeset y compara su posición anterior/actual contra el centro actual del AOI.
No garantiza added/removed de un Xenoform inmóvil cuando se mueve el observador.
La prueba travel_aoi_test cubre una entidad móvil respecto de otros observadores,
pero no el caso inverso. No se ejecutó una reproducción en esta etapa de análisis.

**PROVISIONAL M3 - requiere aprobación**: conjunto de IDs conocidos por conexión,
ubicado en las sesiones de WebSocketGateway. No indexarlo sólo por player_id,
porque dos conexiones del mismo jugador pueden tener baselines distintos.

1. Inicializar/reemplazar el conjunto con IDs del full_snapshot enviado.
2. Consultar los IDs visibles actuales usando SpatialHash y filtro existente.
3. current menos known -> added completo; known menos current -> removed.
4. Intersección de ambos conjuntos y entidades cambiadas -> updated.
5. Actualizar el conjunto de esa conexión después de publicar el delta.
6. Descartar el conjunto al cerrar/recrear la conexión; desync/full_snapshot lo rebasan.

Cada ID aparece como máximo en una categoría por delta. No enviar updated para
entidades que esa conexión no conoce. Una entidad retirada del registro desaparece
del conjunto current; las sesiones que no la conocían no reciben removed espurio.
Crear y retirar dentro del mismo ciclo sin publicar no debe dejar una entidad fantasma.
La nave propia permanece conocida desde su snapshot y recibe updated al viajar/llegar.

La propuesta requiere cambiar la API interna delta_for para recibir el baseline
visible de la sesión y adaptar sus llamadores/pruebas. No mantener dos algoritmos
de AOI paralelos. Las expectativas de gameplay M1/M2 se conservan; los fixtures de
tests deberán establecer snapshots/baselines explícitos si cambia la firma.

Gateway debe reconciliar visibilidad en cada tick de sesiones con snapshot inicial,
sin depender exclusivamente de has_changes; si no cambia nada no envía mensajes.
Mantener orden tick -> publicación a todas las sesiones -> acknowledge_changes.
Evitar recorrer todas las entidades: consultar candidatos espaciales y conjuntos
visibles. No transmitir snapshots completos continuamente ni agregar ACK/retransmisión.

## 7 Representación cliente

**PROVISIONAL M3 - requiere aprobación**: XenoformRepresentation RefCounted como
copia tipada, equivalente conceptualmente a ShipRepresentation: entity_id,
system_id, config_id, display_name, position: Vector2 y state: String.

WorldState.get_xenoform(entity_id) devuelve esa copia o null para entidad ausente,
otro kind o datos base inválidos. No crear otra lista de enemigos como autoridad
local. Los snapshots/deltas siguen aplicándose al único WorldState existente.

La réplica no carga el catálogo del SSS para adivinar configuración. Un Xenoform
genérico histórico sin config_id se representa con configuración desconocida,
no con m3-demo-static por inferencia. Campos no recibidos quedan desconocidos;
un estado antiguo se conserva tal como fue recibido, sin normalizarlo a IDLE.
La nueva API SSS publica siempre la forma completa acordada.

Conversión de vuelta a Dictionary, si se incorpora para consumidores, devuelve
copia profunda; cambios locales no modifican WorldState ni el SSS. Consultar
nuevamente tras WorldState.changed. No cachear un modelo como estado vivo.

WorldDebugView conserva el marcador xenoform existente y puede diferenciarlo
visualmente con una forma diagnóstica. El panel muestra tipo, ID, config, estado
y posición del objetivo seleccionado; no muestra energía como vida ni ofrece
botón de atacar. Un delta no debe sustituir silenciosamente los datos del objetivo
seleccionado por el panel de nave propia.

## 8 Selección y convivencia con viaje

**REGLA OFICIAL**: un solo sistema para nave propia, ajena, asteroide y Xenoform.

**IMPLEMENTACIÓN ACTUAL**: ShipSelectionState ya selecciona cualquier entity_id
visible y se invalida en removed/snapshot excluyente/clear. Su nombre no lo limita
a naves. get_selected_ship filtra naves y devuelve null para los otros tipos.

**PROVISIONAL M3 - requiere aprobación**: conservar clase, constructor, señal changed,
selected_entity_id y métodos actuales. Añadir sólo get_selected_xenoform como
consulta al mismo WorldState. No renombrar la clase ni crear PveSelectionState.

Limitación de input actual: cuando destination_selection_enabled=true, cualquier
tap dentro del mapa se interpreta como destino antes de buscar una entidad.
Esto impide cambiar directamente de nave propia anclada a Xenoform por tap.

Prioridad propuesta para mouse y touch:

1. Mientras espera resolución de start_travel: conservar bloqueo de tap.
2. Si el tap encuentra entidad dentro del radio actual: seleccionar su entity_id.
3. Si no encuentra entidad y está habilitada preparación de viaje: elegir coordenada.
4. Si no encuentra entidad y no prepara viaje: limpiar selección.

Seleccionar otra entidad cancela el destino provisional local como ya hace
TravelIntentState.select_entity; no cancela un viaje aceptado por el SSS.
Los gestos drag/pan/zoom conservan su comportamiento. Seleccionar Xenoform no
habilita viaje, no inicia Combat y no envía una intención de ataque.

La prioridad de entidad implica que un tap sobre un marcador ya no elige esa misma
coordenada como destino. Es un cambio de interacción explícito que necesita aprobación.
No se decide una futura UX de viaje hacia enemigos en esta rama.

## 9 Comportamiento mínimo

**REGLA OFICIAL**: el objetivo pedido incluye creación autoritativa y sincronización.
La Guía APT respalda spawning dinámico y PvE como objetivos de planificación; su
tarea de spawning menciona configuración de Equipo 5 y spawner procedural.

**PENDIENTE DE DECISIÓN**: no se encontraron reglas suficientes de distribución,
frecuencia, respawn, niveles, persecución, pathfinding, ataques autónomos o contacto
que inicie Combat. Tampoco un formato aprobado de configuración de Equipo 5.

**PROVISIONAL M3 - requiere aprobación**: enemigos estáticos creados explícitamente
por el SSS al bootstrap y mediante la misma API interna después del snapshot para
probar added. Retirada explícita para validar removed. Ninguna decisión autónoma
por tick. Las pruebas pueden ejercitar reubicación mediante infraestructura existente
del mundo para demostrar updated; no convierte esto en una IA o habilidad de movimiento.

No crear timers de spawn, scheduler, proveedor remoto o integración LiveOps para
esta etapa. Configuración local sustituible no equivale a implementar Equipo 5.
El spawning procedural futuro queda pendiente; este slice entrega infraestructura
de creación/retirada dinámica, no una política poblacional terminada.

## 10 Frontera para Combat

**PROVISIONAL M3 - requiere aprobación**:

| Consumidor | Consulta | Resultado y límite |
| --- | --- | --- |
| Cliente Combat/UI | WorldState.get_xenoform(target_entity_id) | Copia XenoformRepresentation visible; null no implica muerte. |
| Cliente selección | ShipSelectionState.get_selected_xenoform() | Copia del mismo WorldState, sin NodePath ni escena. |
| SSS / futuro adaptador Combat | SolarSystemWorld.get_xenoform_target(target_entity_id) | Dictionary de datos copiados o vacío si no existe/no es un Xenoform tipado. |

El objetivo SSS incluye entity_id, kind, system_id, position autoritativa, state,
config_id y energy_cost opcional (null si no configurado). Es una consulta pura,
no un permiso de atacar, reserva de objetivo, inicio de combate o resultado.
No devuelve referencia mutable de EntityState o Resource al consumidor externo.

Combat debe resolver nuevamente la entidad por ID al ejecutar la acción y validar
existencia/sistema/ownership del atacante con autoridad del SSS. El snapshot del
cliente no aporta autoridad. Datos adicionales para su resolver requieren contrato
propio acordado; esta rama no garantiza hp, tropas, resistencias o debilidades.

Cliente y SSS son proyectos Godot separados: no importar XenoformRepresentation
del cliente en el SSS ni exponer Resources por red. La frontera interna de datos
puede consumirse después por un adaptador SSS-SGM, sin construirlo ahora.

## 11 Archivos propuestos para implementación posterior

Esta tabla es un plan, no archivos implementados. Nuevos scripts tendrán su .uid.

| Acción | Ruta | Responsabilidad |
| --- | --- | --- |
| Crear | `server/sss/pve/xenoform_config.gd` | Resource de definición, energía opcional sin balance elegido. |
| Crear | `server/sss/pve/xenoform_state.gd` | Estado específico compatible con EntityState y serializers visibles. |
| Crear | `server/sss/pve/demo_xenoform_config.tres` | Fixture técnico sin energía configurada. |
| Modificar | `server/sss/world/solar_system_world.gd` | Crear/retirar/consultar Xenoforms e integrar reconciliación AOI. |
| Modificar | `server/sss/network/websocket_gateway.gd` | IDs visibles por conexión, baselines de snapshots y publicación. |
| Modificar | `server/sss/mock/mock_world_seed.gd` | Reemplazar dummy por configuración/ID/posición inicial explícitos. |
| Modificar | `server/sss/mock/default_mock_world_seed.tres` | Conectar fixture PvE; conservar IDs/posiciones baseline. |
| Crear | `modules/team3/pve/xenoform_representation.gd` | Copia tipada de la réplica. |
| Modificar | `modules/team3/world/world_state.gd` | Añadir consulta get_xenoform sin duplicar réplica. |
| Modificar | `modules/team3/ships/ship_selection_state.gd` | Consulta específica sobre la selección existente. |
| Modificar | `modules/team3/world/world_debug_view.gd` | Prioridad de entidad/input y representación diagnóstica. |
| Modificar | `app/main.gd` | Panel consistente con objetivo seleccionado; composición existente. |
| Crear | Pruebas PvE indicadas en sección 12 | Validación del vertical slice. |
| Modificar si cambia API AOI | Pruebas SSS existentes que llamen delta_for | Establecer baseline por sesión sin debilitar expectativas. |
| Modificar tras acuerdo explícito | `contracts/sss_protocol_v1.md` | Campos PvE, estado y decisión de versión. |
| Crear al terminar implementación | `docs/team3/TEAM3-M3-WORLD-PVE.md` | Resultados reales y pasos de demo. |
| Modificar al terminar implementación | `docs/TESTING.md` | Registrar pruebas nuevas y resultados sin confundirlos con propuestas. |

No se propone modificar ShipRepresentation, su semántica de IDs, TravelProjection,
las reglas de TravelIntentState, AGENTS.md o documentación histórica. No crear una
escena por enemigo, archivos de Combat/Mining o infraestructura de otros equipos.
Si la implementación revela que necesita otros archivos, ampliar el plan antes de tocarlo.

## 12 Pruebas propuestas

Esta matriz corresponde a la propuesta original. La sección 16 distingue las
pruebas SSS implementadas/ejecutadas de las pruebas cliente/Combat todavía pendientes.

| Archivo propuesto | Casos y evidencia esperada |
| --- | --- |
| `server/sss/tests/m3_xenoform_creation_test.gd` | Alta tipada con ID único, configuración y límites válidos; rechazo sin efectos parciales; dos instancias no comparten estado; energía ausente/alternativa configurable; retirada sin duplicado. |
| `server/sss/tests/m3_xenoform_replication_test.gd` | Snapshot completo; added de runtime; updated incluye datos específicos; removed; una categoría por ID; bootstrap sin duplicar dummy; crear/retirar antes de flush no deja fantasmas. |
| `server/sss/tests/m3_xenoform_aoi_test.gd` | Dentro/fuera y límites actuales; Xenoform inmóvil entra/sale cuando viaja observador; regreso produce added completo; dos sesiones independientes, incluidas dos del mismo jugador; consulta de una sesión no drena ChangeSet. |
| `server/sss/tests/m3_xenoform_target_test.gd` | Consulta por ID sin escena, sólo kind tipado correcto, posición autoritativa, datos copiados, config y energía null; ausencia tras retirada; copia no cambia Resource/entidad. |
| `tests/m3_xenoform_representation_test.gd` | Full/delta/removed, reemplazo del bloque anidado completo, getter tipado, copias aisladas, datos históricos desconocidos sin inventar config/IDLE; reconstrucción de snapshot tras clear. |
| `tests/m3_xenoform_selection_test.gd` | Mouse y touch sobre propia/ajena/asteroide/Xenoform; cambio de objetivo mientras prepara destino; vacío conserva preparación M2; bloqueo pendiente; updated conserva selección; removed/snapshot excluyente/clear invalidan. |
| `tests/m3_xenoform_scene_test.gd` | SSS real crea objetivo, snapshot/delta llegan al cliente real, panel conserva objetivo, selección entrega sus datos a un consumidor sin escena, reconexión reconstruye objetivos y el viaje M2 sigue funcionando. |

La prueba E2E debe comprobar al menos una creación posterior al snapshot, no sólo
el seed inicial. Un harness del SSS de pruebas puede llamar la API de producción
en instantes controlados; no agregar mensajes de spawn/debug al protocolo ni
métodos de producción que sólo existan para satisfacer el test.

Regresión obligatoria después de implementar:

- Cliente: m1_client_world_state_test y m1_sss_connection_sequence_test.
- SSS: entity_registry_test, spatial_hash_test, aoi_test, world_snapshot_test,
  world_snapshot_multi_test, world_delta_test y changeset_lifecycle_test.
- M2 cliente: m2_sss_connection_test, m2_travel_intent_test,
  m2_travel_projection_test y m2_world_debug_view_test.
- M2 SSS: travel_math_test, travel_start_test, travel_snapshot_test,
  travel_delta_test, travel_tick_test y travel_aoi_test.
- Nave/Selección: m3_ship_representation_test, m3_ship_selection_test y
  m3_ship_scene_test con cliente/SSS reales.

Los smoke tests históricos M0/M1 usan protocolos anteriores; no contarlos como
E2E del runtime M2. Ejecutar Godot 4.6.2, registrar versión/HEAD/comandos/marcadores
y código de salida. Confirmar cambios de API sin rebajar aserciones de viaje/AOI.

Android: probar tap frente a drag, paneo/zoom y diferentes aspect ratios usando
la vista adaptable existente; dibujar sólo entidades visibles, sin IA por frame
o timers por enemigo. Después validar dispositivo físico, background/resume,
pérdida/reconexión y limpieza/reconstrucción. Una simulación touch de PC no
certifica Android físico ni el rendimiento final.

## 13 Decisiones provisionales que necesitan aprobación

| ID | Propuesta |
| --- | --- |
| P1 | Resource XenoformConfig y subtipo estrecho XenoformState; reutilizar registro/índice/changeset. |
| P2 | Forma visible con system_id/display_name/state y bloque xenoform.config_id. |
| P3 | Estado técnico único IDLE; sin HP ni estados de Combat. |
| P4 | Energía opcional configurable, sin tabla seleccionada ni valor activo por defecto; fuera del payload cliente. |
| P5 | Creación/retirada explícita, bootstrap tipado y ausencia de comportamiento autónomo. |
| P6 | Reconciliación por conexión con IDs visibles anteriores y actuales, incluso al moverse el observador. |
| P7 | Reutilizar ShipSelectionState y priorizar entidades sobre coordenadas al tocar/clicar. |
| P8 | Consultas copiadas de objetivo en cliente/SSS; ninguna acción/resolver Combat. |
| P9 | Mantener team3-m2.0 sólo si se acuerda la extensión; documentarla antes de implementarla. |

No implementar una fila no aprobada ni interpretar este documento como aprobación
del contrato. Si se rechaza IDLE, prioridad de input o la extensión, revisar el
diseño antes de programar; no elegir silenciosamente otra regla.

## 14 Contradicciones y cuestiones pendientes

1. **Energía**. OPEN_DECISIONS.md cita costos 3000/5000/8000/14000/18000 en
   `_ai_context/docs/diseno_de_juego.md` frente a 3000/6000/10000/14000/18000
   en `galactum-sgm/src/xeno/catalog.js`. No se elige una tabla como oficial.
   El campo propuesto es costo opcional, no vida. Semántica final y tabla canónica
   requieren decisión; la configuración no resuelve por sí sola la contradicción.
2. **Estado PvE**. EntityState usa ANCHORED para el dummy, pero el contrato sólo
   acuerda esos estados para viaje de nave. IDLE es propuesta nueva, no requisito
   deducido del código. Aprobar su uso y serialización.
3. **AOI esperado frente a cobertura actual**. El contrato permite entradas/salidas
   de visibilidad; el algoritmo actual no cubre estacionarios frente a observador
   móvil. Reconciliar sesiones es una corrección técnica propuesta, no cambiar
   radio/forma de AOI o unidad de coordenadas.
4. **Spawning procedural**. La Guía APT menciona configuración JSON de Equipo 5,
   spawner procedural y coordinación de formato. No contiene políticas concretas
   suficientes para implementarlas aquí. Configuración local M3 es provisional,
   no sustitución oficial del contrato futuro ni LiveOps.
5. **Combate/debilidades/catálogo**. La Guía APT contempla PvE con debilidades y
   combate simplificado; OPEN_DECISIONS.md registra además un catálogo de fuerzas
   contradictorio. Esta rama no decide stats, fórmulas, HP, recompensa o resolver.
6. **Versión/documentación**. El encabezado del contrato llama actual a M1, mientras
   su sección M2 y runtime usan team3-m2.0. No corregir esa deuda ni subir versión
   sin acuerdo; ninguna sección antigua convierte PvE en función ya implementada.
7. **Persistencia, viajes y renderer**. Las decisiones existentes de snapshot
   API/Redis, TimerService/SSS y 2D/3D/orientación permanecen abiertas. M3 usa el
   baseline en memoria y la vista diagnóstica sin decidir presentación final.

La falta de fuentes originales accesibles limita la confirmación de gameplay.
Si se suministran fuentes adicionales que contradigan esta propuesta, mostrar las
rutas y detener la parte afectada hasta una decisión. No resolver mediante código histórico.

## 15 Etapas siguientes y criterio de cierre

1. Revisar este diseño y aprobar/corregir P1-P9. Acordar con Mining/Combat campos,
   estados, energía opcional y el cambio de interacción/visibilidad.
2. Documentar el contrato aprobado y decisión de versión, sin cambios silenciosos.
3. Ejecutar baseline existente y reproducir con una prueba el caso de AOI del
   observador móvil antes de corregirlo. Escribir pruebas de creación/replicación.
4. Implementar config/estado/API de creación/retirada y consulta SSS; validar
   registro, índice, changeset y serializers, conservando el bootstrap M2.
5. Integrar visibilidad por conexión y comprobar snapshots/deltas de estacionarios,
   múltiples sesiones y navegación M2. Riesgo principal de esta rama.
6. Agregar representación cliente, getter y consulta de selección; adaptar panel
   e input sólo según aprobación. Mantener una réplica y una selección.
7. Completar E2E de alta posterior a snapshot, selección, salida/regreso de AOI,
   reconexión y consulta para Combat; ejecutar toda la regresión M1/M2/M3.
8. Validar Android físico y aspectos visuales, documentar resultados reales,
   limitaciones y pasos de demo. No afirmar validaciones que no se ejecutaron.
9. Preparar informe final para revisión. Commit/push/merge/PR sólo a petición.

El slice estará terminado cuando la instancia provenga de la API autoritativa,
todos los caminos de réplica y selección funcionen y estén probados, Combat pueda
consultar copias por ID y la regresión siga pasando. Un marcador creado sólo en
cliente, un snapshot que no pueda recuperar deltas o un AOI sin salida de entidades
inmóviles no satisfacen el objetivo.

Posibles conflictos de integración: SolarSystemWorld/EntityState usados por
Mining/Combat, serializers de tipos, WebSocketGateway, WorldState, selección y
app/main.gd. Mantener cambios PvE específicos en su subtipo y campos namespaced;
coordinar API AOI y contrato antes de integrar. Este análisis no copia ni modifica
el trabajo de las otras ramas.

El análisis inicial sólo creó este documento. La implementación SSS posterior se
registra a continuación; AGENTS.md y código cliente permanecen sin modificaciones.

## 16 Resultado de ETAPA 2

Autorización: instrucción del usuario «APROBADO ETAPA 2». Rama
feature/team3-m3-world-pve, baseline HEAD 2899abb. Trabajo sin commit/push/merge/PR.
Fecha de verificación: 2026-10-14; Godot 4.6.2 stable oficial, Windows.

### Implementación efectiva

- XenoformConfig Resource: config_id, display_name, has_energy_cost y energy_cost.
  Configuración inválida impide alta; energía desactivada no significa costo cero.
  El fixture no activa costo. No se seleccionó ninguna tabla contradictoria.
- XenoformState: instancia EntityState con ID, sistema, posición y estado técnico
  IDLE; configuración copiada por instancia y acceso mediante get_configuration()
  que devuelve otra copia. display_name es dato mutable de la instancia.
- Serializers con whitelist: entity_id/kind/system_id/position/display_name/state
  y xenoform.config_id. Nunca publican energía, ownership de nave, payload arbitrario
  o travel. Cada bloque anidado serializado es una copia independiente.
- SolarSystemWorld.spawn_xenoform(entity_id, configuration, position) devuelve
  XenoformState o null; valida antes de registrar. remove_xenoform(entity_id)
  retira sólo Xenoforms tipados y devuelve bool. ID PvE retirado no se recicla
  durante esta ejecución. No hay generador persistente ni API de creación por red.
- Registro e índice espacial existentes contienen la misma instancia; cambios
  pasan por WorldChangeSet. Bootstrap limpia cambios antes de las sesiones.
- El seed de desarrollo reemplaza el dummy con un Xenoform tipado conservando el
  ID ...0009 y posición (310,315). No se duplica el fixture.
- visible_entity_ids_for(player_id) consulta AOI/SpatialHash existentes y filtra
  por posición autoritativa; conserva radio/forma M2 y ordena IDs para salida estable.
- delta_for(player_id, known_entity_ids: Array[String]) requiere baseline explícito.
  Hace added/removed por diferencia de conjuntos y updated de cambios para IDs
  conocidos todavía visibles. Deduplica actualizaciones por ID y excluye fantasmas
  de altas/bajas ocurridas antes de publicar. No drena ni modifica el baseline.
- Gateway conserva ese baseline por conexión después del snapshot, lo reemplaza
  al pedir otro full_snapshot y no publica deltas antes del snapshot inicial.
  Reconcilia cada tick; sesiones diferentes no consumen los cambios de otras.
- Si una escritura WebSocket falla, cierra esa conexión para reconstruir mediante
  reconexión/snapshot. Sólo avanza seq y baseline cuando la escritura es aceptada
  por WebSocketPeer; esto no es ACK de recepción ni retransmisión propia.
- Posición PvE fuera del mapa se rechaza al usar set_entity_position existente.
  Reubicación interna permite verificar updates; no se agregó movimiento autónomo.

El contrato se extendió explícitamente en contracts/sss_protocol_v1.md con los
campos PvE/IDLE y visibilidad por conexión, conservando team3-m2.0. No cambia
start_travel, estados de nave o el sobre. Los consumidores estrictos de entidades
deben aceptar la extensión al integrar las ramas.

### Archivos efectivos

Nuevos (más .uid de los scripts):

- server/sss/pve/xenoform_config.gd
- server/sss/pve/xenoform_state.gd
- server/sss/pve/demo_xenoform_config.tres
- server/sss/tests/m3_xenoform_creation_test.gd
- server/sss/tests/m3_xenoform_replication_test.gd
- server/sss/tests/m3_xenoform_aoi_test.gd
- server/sss/tests/m3_xenoform_gateway_test.gd
- server/sss/tests/support/aoi_test_replica.gd (baseline contractual sólo para pruebas)

Modificados en ETAPA 2:

- server/sss/world/solar_system_world.gd
- server/sss/network/websocket_gateway.gd
- server/sss/mock/mock_world_seed.gd
- server/sss/mock/default_mock_world_seed.tres
- server/sss/tests/changeset_lifecycle_test.gd
- server/sss/tests/world_delta_test.gd
- server/sss/tests/travel_aoi_test.gd
- server/sss/tests/travel_delta_test.gd
- contracts/sss_protocol_v1.md
- Este documento (creado en análisis y actualizado en ETAPA 2).

Las cuatro pruebas existentes adaptadas establecen sus baselines mediante
snapshot y aplican added/removed con un helper de pruebas. No se eliminan ni
rebajan sus expectativas previas de mundo/viaje.

### Pruebas y resultados

Baseline SSS: 13 pruebas existentes OK antes de implementar. Las tres pruebas
nuevas iniciales fallaron por funciones ausentes y por el caso de observador
móvil frente a enemigo inmóvil, antes de la implementación.

| Prueba SSS nueva | Resultado | Cobertura efectiva |
| --- | --- | --- |
| m3_xenoform_creation_test | OK, salida 0 | IDs, creación atómica, validación, configuración/estado aislados, energía configurable artificial, whitelist y retirada. |
| m3_xenoform_replication_test | OK, salida 0 | Bootstrap, snapshot, alta posterior, updated específico, posición, deduplicación, removed y reconstrucción sin fantasmas. |
| m3_xenoform_aoi_test | OK, salida 0 | Observador viajando frente a entidad inmóvil, salida/regreso, límites del AOI, baselines independientes y removed sin destrucción. |
| m3_xenoform_gateway_test | OK, salida 0 | WebSocket real, sobre/seq, alta/datos actualizados en dos conexiones del mismo jugador, baseline inicial, snapshot de recuperación y reconexión. |

Regresión SSS (cada una OK, salida 0): aoi_test, changeset_lifecycle_test,
entity_registry_test, spatial_hash_test, world_snapshot_test,
world_snapshot_multi_test, world_delta_test, travel_math_test, travel_start_test,
travel_snapshot_test, travel_delta_test, travel_tick_test y travel_aoi_test.
entity_registry_test imprime errores esperados por duplicado/ID inexistente;
son casos negativos del baseline y no fallos de la suite.

Regresión cliente sin modificar código (cada una OK, salida 0):
m1_client_world_state_test, m1_sss_connection_sequence_test,
m2_sss_connection_test, m2_travel_intent_test, m2_travel_projection_test,
m2_world_debug_view_test, m3_ship_representation_test y m3_ship_selection_test.
La demo m3_ship_scene_test contra SSS real también terminó OK, salida 0,
verificando viaje y reconstrucción M2. Total: 26 pruebas ejecutadas y aprobadas
(17 SSS y 9 cliente, incluida la demo contra el SSS actualizado).

La prueba WebSocket inicial comparaba Arrays enteros internos contra números
float que JSON.parse_string reconstruye; se confirmó que ningún campo se perdía
y se corrigió la expectativa de red con datos literales. No se cambió precisión
de serialización ni reglas de coordenadas para hacer pasar esa comparación.

### Límites y pendientes de ETAPA 3

No se implementaron XenoformRepresentation, WorldState.get_xenoform(),
get_selected_xenoform(), prioridad nueva de input o UI. Tampoco
get_xenoform_target(), resolver, ataque, HP, debilidades, economía, loot,
progresión, IA, spawn procedural, respawn, integración Equipo 5 o persistencia.
El cliente genérico previo puede recibir el kind, pero no equivale a haber
implementado la representación/selección tipada PvE de ETAPA 3.

ETAPA 3 debe incorporar la réplica tipada y selección existente según su
aprobación, panel/input y E2E de la escena PvE, sin iniciar Combat completo.
Android físico y rendimiento/carga no se certifican por estas pruebas PC.

Riesgos de integración: nueva firma delta_for y serializers específicos requieren
adaptación de llamadores de otras ramas. Baselines por conexión agregan memoria
proporcional a entidades visibles; el registro de IDs PvE usados crece durante
la ejecución para impedir reciclaje. Evaluación de carga prolongada queda pendiente.
El estado continúa en memoria: un reinicio SSS vuelve al seed, no reconstruye
enemigos de runtime desde almacenamiento persistente. La contradicción de energía
permanece abierta aunque el valor ya sea configurable.

## 17 Resultado de ETAPA 4

Autorización: instrucción del usuario «APROBADO ETAPA 4». Sólo selección e
inspección mínima del cliente; no se implementa ETAPA 5 ni Combat. Los cambios
SSS/contrato de ETAPA 2 ya estaban presentes sin commit y se conservaron.

### Alcance y archivos

Modificados en esta etapa:

- modules/team3/ships/ship_selection_state.gd: get_selected_entity() devuelve
  una copia de WorldState.get_entity(selected_entity_id). Mantiene el mismo ID,
  señal changed y limpieza existente; no agrega otro sistema de selección.
- modules/team3/world/world_debug_view.gd: entidad bajo tap/click tiene prioridad
  sobre coordenada de destino. Tap en espacio vacío conserva preparación de viaje.
  Arrastre/paneo y zoom permanecen; bloqueo de tap durante solicitud pendiente intacto.
- app/main.gd: el panel existente ShipLabel inspecciona el objetivo seleccionado.
  _refresh_ship_label se reemplaza por _refresh_selection_label; ya no sustituye
  Xenoform/asteroide seleccionado por nave propia después de un map_delta.
- Este documento: resultados efectivos, límites y verificación.

Nuevos, con sus archivos .uid:

- tests/m3_xenoform_selection_test.gd
- tests/m3_xenoform_inspection_test.gd
- tests/m3_xenoform_scene_test.gd

WorldState, escena main.tscn, ShipRepresentation, lógica de viaje y transporte
no se modificaron en ETAPA 4. Tampoco SSS, contrato, AGENTS.md u OPEN_DECISIONS.md.
Se usa la réplica genérica ya disponible; no se crean XenoformRepresentation,
get_xenoform(), get_selected_xenoform() o interfaces/acciones Combat.

### Flujo de selección e inspección

1. SSS publica el Xenoform de ETAPA 2; el marcador genérico existente lo representa.
2. Mouse/touch selecciona entity_id mediante WorldDebugView y ShipSelectionState.
3. El panel muestra tipo/kind, entity_id, estado y posición recibidos; nombre si
   está disponible y config_id para Xenoforms. Naves incluyen sus IDs recibidos.
4. Distingue nave propia, nave ajena con ownership conocido, asteroide y Xenoform.
   Ownership no recibido se muestra como desconocido; no se inventa propietario.
5. Cambios del mundo refrescan datos del mismo objetivo. removed, snapshot
   excluyente o WorldState.clear invalidan la selección y limpian el panel.
   No se muestra muerte/destrucción ni se selecciona otra entidad automáticamente.
6. Reentrada/reconstrucción devuelve el marcador y permite volver a seleccionarlo,
   pero no restaura por inferencia una selección invalidada.

Cambiar de nave propia a entidad inspeccionada descarta sólo el destino provisional
local según TravelIntentState existente. No cancela un viaje aceptado. Durante
una solicitud pendiente el input de tap continúa bloqueado. Seleccionar un Xenoform
no habilita Confirmar viaje ni agrega un botón de atacar, HP, energía o resultados.

### Verificación

Godot 4.6.2 stable en Windows. Las dos pruebas iniciales fallaron antes de los
cambios y pasaron después. Se verificó la escena real contra un SSS de desarrollo.

| Prueba nueva | Resultado | Cobertura |
| --- | --- | --- |
| m3_xenoform_selection_test | OK, salida 0 | Mouse/touch de cuatro tipos, prioridad sobre destino, bloqueo pendiente, drag, resize/zoom, copia aislada, updated, AOI, snapshot excluyente y clear. |
| m3_xenoform_inspection_test | OK, salida 0 | Escena/panel reales con mensajes controlados, clasificación, estado/nombre/config, invalidación, objetivo conservado durante deltas y convivencia con preparación/confirmación/llegada de viaje. |
| m3_xenoform_scene_test | OK, salida 0 | Xenoform recibido de SSS real, mouse/touch desde nave propia, inspección, snapshot de recuperación y reconstrucción sin selección automática. |

Regresión: las 8 pruebas cliente puras de M1/M2/Nave-Selección, la demo
m3_ship_scene_test contra SSS real y las 17 pruebas SSS de ETAPA 2.
Resultado final: 29 pruebas OK, cada una con código de salida 0 (17 SSS y
12 cliente, incluidas las dos demos contra SSS real). No se incluyen smoke tests
históricos de versiones anteriores. git diff --check no informó errores.

La prueba de inspección usa datos de red controlados para cubrir salida AOI y
snapshot excluyente en la escena. La prueba de escena usa red real para recepción,
inspección y reconstrucción. AOI autoritativo se verifica por separado en la suite SSS.

### Riesgos y límites

- El click/tap sobre un marcador selecciona la entidad, incluso preparando viaje;
  ya no elige esa coordenada como destino. Cambio de interacción aprobado en el diseño.
- Se conservan nombre de clase ShipSelectionState y control ShipLabel para reducir
  conflictos; ahora incluyen inspección genérica. Otras ramas deben conservar la
  selección compartida y adaptar referencias al helper privado renombrado.
- No hay validación de Android físico o render final. La importación informa
  build-tools Android no disponibles; touch se probó con eventos simulados en PC.
- La representación tipada específica PvE no existe todavía; esta selección usa
  los datos aprobados del único WorldState. No es un resolver ni autorización Combat.
- No se realizó commit, push, merge o PR. No se avanzó a ETAPA 5.

## 18. ETAPA 5 — Política PvE mínima implementada

### Revisión documental y alcance

Se revisaron nuevamente AGENTS.md, contracts/sss_protocol_v1.md,
docs/team3/OPEN_DECISIONS.md, este diseño, documentación M2/M3 disponible,
código y pruebas actuales. Se leyó el contenido del DOCX de planificación
lucas_mateo/1.5_GuiaEstudiante_Fase 1_Definicion Proyecto APT.docx.

- **REGLA OFICIAL**: SSS autoritativo; cliente representa; configuración separada;
  snapshot/delta/AOI existentes; removed no implica necesariamente destrucción.
  El usuario prohíbe ampliar esta etapa con IA compleja, persecución, ataques
  autónomos, pathfinding, loot, recompensas o spawning dinámico avanzado.
- La Guía APT menciona spawning, contacto y PvE como objetivos generales, y una
  futura tarea de spawner procedural que consume configuración de Equipo 5.
  No define frecuencias, distribución, transiciones, objetivos, rangos ni
  condiciones de movimiento/ataque suficientes para ejecutarlos en esta etapa.
  La mención de un resolver determinista no especifica comportamiento autónomo.
- **PROVISIONAL M3 - aprobado para esta etapa**: STATIC con estado inicial IDLE,
  ya usado en el contrato/diseño de esta rama. Es una política técnica de prueba;
  no se declara comportamiento final oficial de Galactum.
- **PENDIENTE DE DECISIÓN**: comportamiento activo bloqueado hasta disponer de
  reglas operativas acordadas. Las fuentes externas históricas citadas por
  OPEN_DECISIONS.md no están disponibles; no se afirma haberlas releído.

### Implementación efectiva

Se reutiliza la infraestructura existente, sin agregar un motor de IA o máquina
completa de estados. XenoformConfig expone behavior_mode e initial_state separados
del estado mutable. Sólo STATIC/IDLE son válidos actualmente. Una configuración
con modo o estado inicial no implementado rechaza el spawn antes de alterar
registro, índice espacial o ChangeSet. Antes esos campos no existían y una
asignación desconocida no era una política validada; no había persecución activa.

XenoformState inicializa su estado desde la copia privada de configuración
validada por SolarSystemWorld.spawn_xenoform. Cambiar después el Resource fuente
no cambia las instancias creadas. El fixture m3-demo-static declara la política
explícitamente. Los ticks conservan IDLE y posición, sin decisiones aleatorias,
transiciones temporales ni actualizaciones periódicas espurias.

No se agregan campos de red: la serialización pública y la reconciliación AOI
permanecen como en ETAPA 2. La configuración de comportamiento es interna al SSS.
No hay dependencia de UI o resolver Combat. No se implementa modificación de
política en caliente; cualquier política futura requiere reglas y nuevas pruebas.

### Archivos de esta etapa

Modificados respecto de ETAPA 4:

- server/sss/pve/xenoform_config.gd: política inicial y validación estricta.
- server/sss/pve/xenoform_state.gd: inicialización desde configuración aislada.
- server/sss/pve/demo_xenoform_config.tres: fixture estático explícito.
- docs/team3/TEAM3-M3-WORLD-PVE-DESIGN.md: alcance, bloqueo y resultados.

Creados:

- server/sss/tests/m3_xenoform_behavior_test.gd
- server/sss/tests/m3_xenoform_behavior_test.gd.uid

Los cambios pendientes de etapas anteriores siguen presentes. Esta etapa no
modifica contrato, AGENTS.md, OPEN_DECISIONS.md, UI, selección ni resolver Combat.

### Pruebas y resultados

Godot 4.6.2 stable oficial, Windows, headless. La prueba nueva falló antes del
cambio y pasó después. Comprueba rechazo atómico de políticas no implementadas,
configuración aislada, inicialización, posición y estado estables, ausencia de
deltas espurios y snapshots reproducibles entre dos mundos con las mismas
entradas. Incluye tiempos repetidos, saltos grandes y retroceso del reloj.
No pretende validar comportamiento activo ni recuperación tras reiniciar SSS.

Todas las siguientes pruebas terminaron OK, con código de salida 0:

| Grupo | Pruebas | Resultado |
| --- | --- | --- |
| SSS base (5) | aoi_test, changeset_lifecycle_test, entity_registry_test, spatial_hash_test, world_delta_test | 5/5 OK |
| SSS snapshots (2) | world_snapshot_multi_test, world_snapshot_test | 2/2 OK |
| SSS viaje (6) | travel_aoi_test, travel_delta_test, travel_math_test, travel_snapshot_test, travel_start_test, travel_tick_test | 6/6 OK |
| SSS Xenoform (5) | m3_xenoform_aoi_test, m3_xenoform_behavior_test, m3_xenoform_creation_test, m3_xenoform_gateway_test, m3_xenoform_replication_test | 5/5 OK |
| Cliente M1 (2) | m1_client_world_state_test, m1_sss_connection_sequence_test | 2/2 OK |
| Cliente M2 (4) | m2_sss_connection_test, m2_travel_intent_test, m2_travel_projection_test, m2_world_debug_view_test | 4/4 OK |
| Cliente Nave (2) | m3_ship_representation_test, m3_ship_selection_test | 2/2 OK |
| Cliente Xenoform (2) | m3_xenoform_selection_test, m3_xenoform_inspection_test | 2/2 OK |
| Escenas contra SSS real (2) | m3_xenoform_scene_test, m3_ship_scene_test | 2/2 OK |

Total: 30/30 (18 SSS y 12 cliente). entity_registry_test emite los errores
esperados de sus casos negativos antes de terminar OK. La regresión cubre
snapshot, delta, AOI, removed, reconstrucción, selección mouse/touch y viaje.
No se ejecutó prueba en Android físico ni se validó rendimiento móvil.

### Decisiones pendientes y límites

- Definir reglas operativas de comportamiento activo y transiciones antes de
  habilitar otros modos/estados. No se implementan persecución, ataques autónomos,
  pathfinding, spawning procedural, loot, recompensas, economía o progresión.
- Acordar configuración de spawning con Equipo 5 cuando corresponda. El seed
  actual sigue siendo un mock explícito de desarrollo.
- Resolver la contradicción de energía ya registrada en OPEN_DECISIONS.md.
  Ninguna tabla se adopta como oficial y energía no se transforma en vida.
- STATIC/IDLE sólo valida la política de creación actual; no establece reglas
  de daño, muerte, combate o transiciones futuras.
- No se avanzó a ETAPA 6. No se realizó commit, push, merge o PR.

## 19. ETAPA 6 — Punto de integración con Combat implementado

### Frontera interna SSS

**PROVISIONAL M3 - aprobado para esta etapa**: se implementa la consulta prevista
por la sección 10, sin resolver ni adaptador SSS-SGM. Firma pública:

```gdscript
func get_xenoform_target(entity_id: String) -> Dictionary
```

Pertenece a SolarSystemWorld. Devuelve {} si no existe o no es una instancia de
XenoformState. Una entidad histórica con kind xenoform pero sin modelo tipado no
obtiene datos inventados. El resultado para un objetivo válido tiene estas claves:

| Campo | Tipo en la interfaz interna | Semántica |
| --- | --- | --- |
| entity_id | String | Identidad actual del objetivo. |
| kind | String | xenoform. |
| system_id | String | Sistema autoritativo. |
| position | Array de dos int | Coordenadas actuales del SSS, [x, y]. |
| state | String | Estado autoritativo actual; actualmente IDLE. |
| config_id | String | Identificador de configuración de la instancia. |
| energy_cost | int o null | Costo configurado si has_energy_cost; null si no está configurado. |

Sólo se exponen esos datos. energy_cost no significa vida, disponibilidad de
energía del atacante, débito o autorización. No se elige una tabla oficial.
La configuración del fixture de desarrollo sigue sin costo habilitado.

Se construye un Dictionary nuevo y un Array de posición nuevo desde la entidad
autoritativa y su configuración aislada. No devuelve EntityState, Resource,
Node o referencia mutable al mundo. La consulta no cambia estado ni ChangeSet,
no inicia interacción ni reserva un objetivo. Las copias son históricas desde
que se devuelven: se debe reconsultar por ID antes de resolver una acción.

### AOI y frontera cliente

**REGLA OFICIAL**: removed puede significar salida de AOI, no destrucción.
La consulta interna del SSS es global al SolarSystemWorld: un objetivo fuera del
AOI sigue consultable si existe. Esto no autoriza atacarlo fuera de AOI. No se
inventa una regla de elegibilidad/rango ni se agrega un player_id opcional que
pudiera confundirse con autorización.

En cliente se conservan WorldState.get_entity(entity_id) y la selección compartida
ShipSelectionState.get_selected_entity(). Devuelven copias de la réplica visible;
tras removed, snapshot excluyente o clear, el objetivo deja de estar disponible y
la selección se invalida, tal como cubren las pruebas de ETAPA 4. No se duplica
WorldState. La representación tipada y get_xenoform/get_selected_xenoform de la
propuesta de ETAPA 3 siguen sin implementarse; no son necesarios para este punto
interno SSS y no se incorporan por inferencia.

### Instrucciones para feature/team3-m3-combat

1. Recibir la instancia de SolarSystemWorld por composición en el componente SSS
   que consume la consulta; no buscar una escena ni crear un Autoload.
2. Conservar target_entity_id como identificador, no una referencia de escena.
3. Consultar world.get_xenoform_target(target_entity_id). Si devuelve {}, el
   objetivo ya no está disponible como Xenoform tipado; no resolver con una copia
   anterior ni asumir automáticamente muerte.
4. Consumir los campos documentados, reconsultando al ejecutar. La selección o
   snapshot cliente sólo sirve para identificar el objetivo propuesto.
5. Combat debe validar con autoridad identidad del atacante, existencia/sistema
   actual y reglas de elegibilidad acordadas antes de resolver. Esta consulta no
   implementa esas reglas, daño, consumo, cooldown, resultado o reserva.
6. Tratar energy_cost == null como dato no configurado; no convertirlo en gratis
   ni usar un valor de una de las tablas contradictorias. Acordar requisitos de
   datos faltantes antes de habilitar una resolución que los necesite.
7. Si el resolver vive en otro proceso/SGM, acordar el adaptador/transporte por
   separado. Esta API interna GDScript no es un endpoint de red nuevo.

Dependencias: SolarSystemWorld -> EntityRegistry -> XenoformState/XenoformConfig
ya existentes. Combat podrá depender de esta API; mundo no importa Combat ni UI.
No hay dependencia circular, lectura/copia de la rama Combat ni merge de ramas.
El único archivo de producción tocado en esta etapa es solar_system_world.gd;
puede requerir resolver un conflicto textual cuando Combat modifique ese mismo
archivo. Preservar la consulta y las garantías AOI de las etapas anteriores.

### Archivos de esta etapa

Modificados respecto de ETAPA 5:

- server/sss/world/solar_system_world.gd: consulta get_xenoform_target.
- docs/team3/TEAM3-M3-WORLD-PVE-DESIGN.md: contrato interno e integración efectiva.

Creados:

- server/sss/tests/m3_xenoform_target_test.gd
- server/sss/tests/m3_xenoform_target_test.gd.uid

No se modifica contracts/sss_protocol_v1.md en esta etapa. Su cambio pendiente
corresponde a ETAPA 2. No se modifica AGENTS.md, configuración de balance, UI,
selección, minería, resolver Combat ni archivos de otras ramas.

### Pruebas y resultados

Godot 4.6.2 stable oficial, Windows/headless. La prueba nueva falló inicialmente
por ausencia de la consulta y pasó después de implementarla.

m3_xenoform_target_test: OK, salida 0. Cubre objetivo válido, esquema de datos
consumible sin escena, ID vacío/inexistente, nave o dummy no tipado, posición
actual, aislamiento de copias/configuración, dos costos técnicos distintos,
costo deshabilitado null aunque exista un valor residual, consulta sin efectos
sobre ChangeSet/red, salida de AOI y ausencia tras retirada real.
Los costos 17 y 29 son fixtures de prueba, no valores oficiales ni defaults.

Regresión completa: las 30 pruebas de la sección 18 vuelven a pasar, cada una
con salida 0, incluidas las dos escenas contra un SSS local real. Total ETAPA 6:
31/31 OK (19 SSS y 12 cliente). Incluye creación, política estática, replicación,
snapshot/delta/AOI/removed/reconstrucción, selección mouse/touch y viaje M1/M2.
entity_registry_test conserva sus mensajes esperados de casos negativos.
git diff --check sin errores. No hay verificación en Android físico.

### Decisiones abiertas

- Tabla canónica de energía y reglas del atacante para resolver con costo ausente.
- Datos futuros de resolución (vida, fuerzas, resistencias/debilidades) y sus
  reglas: no se agregan atributos sin definición.
- Elegibilidad de objetivo (rango/AOI/estados), concurrencia/reserva y frontera
  SSS-SGM cuando se integre Combat. Esta consulta es lectura, no autorización.
- Comportamiento PvE activo y spawning permanecen pendientes según sección 18.
- No se avanzó a ETAPA 7. No se realizó commit, push, merge o PR.
