# Decisiones abiertas de Equipo 3

Estas cuestiones no se resuelven en TEAM3-M0. Las fuentes se clasifican como documentacion oficial/normalizada o codigo historico; una implementacion historica no se toma automaticamente como requisito.

Las rutas relativas indicadas abajo parten de `C:\Galactum\Galactum-20260828T023045Z-1-001\Galactum`.

## Viajes: TimerService o SSS

- Equipo 1 asigna a `TimerService` la ejecucion de timers persistentes, incluyendo viajes: `_ai_context\docs\equipo_1_plataforma_y_backend_core_spec_de_desarrollo.md`.
- Equipo 3 describe al SSS como autoridad del movimiento/viaje y mantiene el estado efimero por timestamps: `_ai_context\docs\equipo_3_mundo_y_combate_spec_de_desarrollo.md` y `_ai_context\docs\plan_de_desarrollo_equipo_3.md`.
- Falta definir quien crea, persiste, recupera y completa un viaje, y como se evita doble autoridad.

## Snapshot via API o Redis

- La estrategia de integracion habla de snapshots via API: `_ai_context\docs\estrategia_de_integracion.md`.
- Los documentos de Equipos 1 y 3 describen snapshots periodicos del SSS en Redis: `_ai_context\docs\equipo_1_plataforma_y_backend_core_spec_de_desarrollo.md` y `_ai_context\docs\equipo_3_mundo_y_combate_spec_de_desarrollo.md`.
- Falta definir el canal canonico y su contrato de recuperacion. M0 no usa ninguno: el snapshot solo vive en memoria y viaja por WebSocket.

## Semantica de `anchor`

- El endpoint/protocolo de Equipo 3 enumera `anchor`: `_ai_context\docs\endpoints_equipo_3.md`.
- La especificacion y el codigo historico sugieren anclaje automatico al llegar: `_ai_context\docs\equipo_3_mundo_y_combate_spec_de_desarrollo.md` y `galactum-sss\scripts\main.gd`.
- Falta definir si es un comando explicito, un estado derivado, o ambos, y sus transiciones validas.

## Grid o coordenadas float

- La documentacion actual del Equipo 3 define mapa 600x600, celdas y AOI de 50 celdas: `_ai_context\docs\equipo_3_mundo_y_combate_spec_de_desarrollo.md`.
- Codigo/contratos historicos del cliente contienen posiciones continuas/float: `galactum-client\src\api\index.js` y `galactum-client\src\stores\game.js`.
- Falta fijar unidad, precision, conversion visual y limites. M0 transporta enteros de diagnostico sin declarar la decision final.

## Catalogo oficial de fuerzas

- El diseno general presenta Infanteria, Drones y Pilotos, con Escudos y Canoneros: `_ai_context\docs\diseno_de_juego.md`.
- Material historico usa un catalogo circular diferente (assault/heavy/sniper/mech/drone): `galactum-sgm\src\combat\constants.js` y `galactum-client\src\data\troops.js`.
- Falta una fuente canonica versionada antes de implementar combate.

## Valores de energia de xenoformas

- El diseno general indica costos 3000/5000/8000/14000/18000: `_ai_context\docs\diseno_de_juego.md`.
- El catalogo historico usa 3000/6000/10000/14000/18000: `galactum-sgm\src\xeno\catalog.js`.
- No se elige una tabla en M0.

## Alcance de captura de Comandante

- La estrategia de integracion incluye captura de Comandante como capacidad de Equipo 3: `_ai_context\docs\estrategia_de_integracion.md`.
- El plan del Equipo 3 la deja como diseno tecnico/post-lanzamiento: `_ai_context\docs\plan_de_desarrollo_equipo_3.md`.
- Falta decidir si pertenece al entregable inicial, una fase posterior o integracion con otro equipo.

## 2D/3D y orientacion

- Los documentos revisados no fijan 2D o 3D, orientacion de pantalla ni renderer definitivo: `_ai_context\docs\equipo_3_mundo_y_combate_spec_de_desarrollo.md`, `_ai_context\docs\plan_de_desarrollo_equipo_3.md` y `_ai_context\docs\diseno_de_juego.md`.
- M0 usa una vista `Control` diagnostica y layout adaptable; esto no decide la presentacion final.

## Ubicacion futura del combate dentro del SGM

- La documentacion asigna resolucion determinista de combate al SGM e integracion SSS-SGM: `_ai_context\docs\equipo_3_mundo_y_combate_spec_de_desarrollo.md` y `_ai_context\docs\plan_de_desarrollo_equipo_3.md`.
- Existe un modulo historico en `galactum-sgm\src\combat\`, pero no establece donde debe vivir en el repositorio nuevo.
- TEAM3-M0 no crea `backend/team3-combat/` ni otra ubicacion provisional.
