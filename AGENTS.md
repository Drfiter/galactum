# Galactum — Equipo 3: Mundo y Combate

## Objetivo

Este repositorio contiene la implementación en Godot del módulo:

**Equipo 3 — Mundo y Combate**

La prioridad es entregar el trabajo correspondiente al Equipo 3 funcionando de forma independiente.

No es necesario implementar Galactum completo.

La arquitectura debe permitir posteriormente integrar o desarrollar sistemas de los otros equipos sin tener que rehacer los sistemas principales del Equipo 3.

---

## Plataforma

- Godot 4.x
- GDScript tipado
- Target principal: Android
- Debe funcionar también en PC durante desarrollo

Considerar desde el inicio:

- controles táctiles;
- diferentes resoluciones y aspect ratios;
- rendimiento móvil;
- memoria;
- background/resume;
- separación entre lógica y presentación;
- futura integración con backend.

No asumir 2D, 3D, orientación de pantalla ni renderer definitivo si la documentación oficial no lo establece.

---

## Alcance del Equipo 3

El Equipo 3 es responsable principalmente de:

- mundo y mapa;
- entidades del mundo;
- representación de nave/flota;
- selección;
- navegación;
- movimiento;
- asteroides;
- minería;
- enemigos y PvE;
- combate;
- resultados de interacciones;
- UI necesaria para estas funcionalidades.

También debe respetarse cualquier responsabilidad adicional del Equipo 3 definida en la documentación oficial.

---

## Fuera del alcance inicial

No implementar sistemas completos de:

- Equipo 1 — Plataforma y Backend Core;
- Equipo 2 — Nave, Economía y Progresión;
- Equipo 4 — Social y Política;
- Equipo 5 — LiveOps, Monetización y Backoffice.

No implementar por iniciativa propia:

- autenticación real;
- economía completa;
- progresión completa;
- alianzas;
- monetización;
- tienda;
- LiveOps;
- backend completo.

---

## Integración con Equipos 1 y 2

Equipo 3 debe poder desarrollarse y demostrarse aunque Equipo 1 y Equipo 2 todavía no estén disponibles.

Las dependencias externas deben quedar desacopladas.

Durante desarrollo pueden utilizarse mocks.

Ejemplo conceptual:

ShipDataProvider
├── MockShipDataProvider
└── RealShipDataProvider

EconomyProvider
├── MockEconomyProvider
└── RealEconomyProvider

PlayerProvider
├── MockPlayerProvider
└── RealPlayerProvider

Los nombres y patrones definitivos deben elegirse según la solución más simple apropiada para Godot.

Mundo, movimiento, minería y combate no deben depender directamente de una API específica de otro equipo.

El objetivo es poder sustituir los mocks posteriormente sin reescribir los sistemas del Equipo 3.

No crear abstracciones para dependencias que todavía no sean utilizadas.

---

## Fuente de verdad

Antes de tomar decisiones importantes de arquitectura o gameplay, revisar la documentación oficial disponible de Galactum.

La documentación y código histórico sirven como referencia.

Distinguir siempre entre:

1. requisito oficial;
2. diseño propuesto;
3. implementación histórica;
4. implementación actual.

No reutilizar código histórico automáticamente.

Si dos fuentes se contradicen:

- indicar las rutas;
- explicar la contradicción;
- no inventar una resolución;
- pedir decisión cuando sea necesaria.

---

## Arquitectura

Priorizar soluciones simples y mantenibles.

Preferir:

- composición;
- señales;
- Resources cuando aporten valor;
- clases con responsabilidades claras;
- GDScript tipado;
- datos separados de lógica;
- lógica separada de presentación.

Evitar:

- sobrearquitectura;
- dependencias circulares;
- referencias globales innecesarias;
- Singletons para todo;
- Service Locators globales;
- Event Bus global sin necesidad;
- clases base universales innecesarias;
- valores de gameplay repartidos como hardcode;
- NodePath como identificador persistente de negocio.

No construir infraestructura futura antes de necesitarla.

---

## Autoloads

No crear Autoloads automáticamente.

Crear un Autoload sólo cuando exista una necesidad real de ciclo de vida global.

Antes de crear uno:

1. explicar qué problema resuelve;
2. explicar por qué un Node normal, Resource o composición no es suficiente.

---

## Datos

Cuando corresponda, usar Resources o modelos de datos para:

- estadísticas de naves;
- enemigos;
- asteroides;
- configuraciones;
- parámetros de combate;
- minería.

Los Resources de configuración no deben contener estado mutable compartido de una partida cuando pueda producir efectos secundarios entre instancias.

Evitar mezclar datos de balance con código de comportamiento.

---

## Identificadores

Mantener identificadores consistentes cuando sean necesarios:

- player_id
- ship_id
- fleet_id
- entity_id
- system_id
- combat_id
- travel_id

No utilizar nombres de Nodes o NodePaths como identificadores persistentes de negocio.

---

## Android

Android debe considerarse desde el comienzo.

No dejar la compatibilidad móvil para el final.

Considerar:

- touch;
- resoluciones;
- aspect ratios;
- rendimiento;
- memoria;
- background/resume;
- futura pérdida y recuperación de conexión.

No hardcodear:

- rutas locales del Android SDK;
- keystores;
- passwords;
- tokens;
- credenciales.

Los ajustes dependientes de una máquina deben documentarse, no versionarse como secretos.

---

## Git

No versionar:

- `.godot/`;
- builds;
- archivos temporales;
- secretos;
- credenciales.

Mantener commits pequeños y relacionados con una sola tarea cuando sea posible.

No realizar commits o push salvo petición explícita.

---

## Trabajo con documentación de referencia

La documentación histórica y oficial de Galactum puede encontrarse fuera de este repositorio.

Cuando esté disponible en el workspace:

- leer primero sólo documentación relevante para la tarea;
- priorizar Equipo 3;
- consultar Equipo 1 y Equipo 2 únicamente cuando exista una dependencia;
- ignorar `node_modules/`, `.git/`, builds y archivos generados salvo necesidad explícita.

No modificar material histórico o documentación fuente salvo petición explícita.

---

## Forma de trabajo de Codex

Codex es principalmente el agente de implementación de este repositorio.

Antes de implementar una tarea:

1. entender el objetivo;
2. revisar archivos y documentación relacionados;
3. identificar dependencias;
4. detectar contradicciones o información faltante;
5. proponer una solución simple;
6. indicar archivos que serán creados o modificados;
7. esperar aprobación cuando la tarea implique una decisión importante de arquitectura;
8. implementar;
9. probar;
10. informar qué cambió y cómo verificarlo.

No expandir el alcance por iniciativa propia.

No inventar requisitos de Galactum.

No implementar funcionalidades de otros equipos salvo petición explícita.

No construir sistemas adicionales únicamente porque podrían ser útiles en el futuro.

---

## Prioridad

La prioridad absoluta es:

**Equipo 3 funcional primero.**

Orden general:

1. Base técnica.
2. Mundo.
3. Nave/flota.
4. Movimiento.
5. Entidades.
6. Minería.
7. PvE.
8. Combate.
9. Android y pulido.
10. Integraciones adicionales.

Este orden puede cambiar si la documentación oficial del Equipo 3 establece dependencias diferentes.

Después de completar el alcance del Equipo 3 podrán implementarse o integrarse funcionalidades adicionales de los demás equipos.