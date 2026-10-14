# Galactum

Galactum es un proyecto desarrollado con Godot para implementar el módulo de mundo y combate de un juego multijugador. Este repositorio contiene el cliente de diagnóstico y el Servidor de Sistema Solar, o SSS, que se comunican mediante mensajes JSON sobre WebSocket.

El estado activo del repositorio es **M2**. M0 y M1 son hitos históricos completados e integrados.

## Problema que resuelve

Un mundo multijugador necesita una fuente única y confiable para el estado compartido. Galactum separa la representación del cliente de la simulación del mundo: el cliente envía intenciones y presenta la información recibida, mientras el SSS mantiene el estado autoritativo y decide qué cambios son válidos.

Esta base permite sincronizar entidades, detectar pérdidas de continuidad en los mensajes y reconstruir el estado del cliente sin confiar en posiciones o resultados calculados por el dispositivo del jugador.

## Público objetivo

> **PENDIENTE DE CONFIRMAR:** el público objetivo formal del producto aún no está definido en la documentación vigente del repositorio.

Durante el desarrollo, el repositorio está dirigido también a integrantes del proyecto, docentes y colaboradores técnicos que necesiten ejecutar o integrar el módulo del Equipo 3.

## Tecnologías y plataformas

| Área | Tecnología |
| --- | --- |
| Motor | Godot 4.6.2 |
| Lenguaje principal | GDScript tipado |
| Transporte | WebSocket |
| Formato de mensajes | JSON |
| Plataformas de desarrollo | PC |
| Plataforma objetivo móvil | Android |

## Arquitectura general

```text
Cliente Godot <-> WebSocket JSON <-> SSS headless
```

El **SSS es autoritativo**. El cliente puede solicitar acciones, pero no determina por sí solo el estado válido del mundo, la posición definitiva de una entidad ni el resultado de una interacción. El SSS valida las intenciones, actualiza la simulación y publica snapshots o deltas.

El repositorio contiene dos proyectos Godot independientes:

- **Cliente:** el proyecto ubicado en la raíz, definido por `project.godot` y con escena principal en `app/main.tscn`.
- **Servidor SSS:** el proyecto headless ubicado en `server/sss`, con su propio `project.godot` y escena principal.

La configuración local predeterminada usa:

- Puerto del SSS: `9100`.
- Mapa de pruebas: `600 x 600`.
- Protocolo activo: `team3-m2.0`.

La arquitectura y el flujo de sincronización se describen en [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Estado del proyecto

| Hito | Estado | Resumen |
| --- | --- | --- |
| M0 | Completado | Conexión cliente-SSS, JSON, versión de protocolo, secuencias, reloj del servidor, snapshot inicial y pong. |
| M1 | Completado e integrado | Sincronización del mundo, `WorldState`, deltas, recuperación de desincronización e interacción con el mapa. |
| M2 | Activo | Flujo de viaje de la nave con validación y simulación autoritativa en el SSS, intención del cliente, proyección visual y ETA. |

El detalle del avance está en [docs/PROJECT_STATUS.md](docs/PROJECT_STATUS.md).

## Requisitos

- Git.
- Godot 4.6.2.
- Puerto TCP `9100` disponible para la configuración predeterminada.
- Dos terminales para ejecutar el SSS y el cliente por separado.

Para exportar o ejecutar en Android se requieren además las plantillas de exportación de Godot y un entorno Android configurado localmente. Las rutas del SDK, claves y credenciales no se versionan.

En los comandos siguientes, `godot` representa el ejecutable de Godot 4.6.2. Si no está disponible en `PATH`, debe reemplazarse por su ruta completa.

## Clonar el repositorio

```powershell
git clone https://github.com/Drfiter/galactum.git
cd galactum
```

Para trabajar con el estado activo de M2, se debe usar la rama que el equipo haya definido como rama de integración o entrega vigente. Al momento de preparar esta documentación, el desarrollo activo se encuentra en `integration/team3-m2`.

## Abrir el cliente

Desde el administrador de proyectos de Godot, importa el archivo `project.godot` de la raíz del repositorio.

También puede abrirse desde una terminal:

```powershell
godot --editor --path .
```

## Iniciar el SSS

Desde la raíz del repositorio:

```powershell
godot --headless --path .\server\sss
```

El puerto puede reemplazarse sin modificar archivos:

```powershell
godot --headless --path .\server\sss -- --port=9200
```

## Ejecutar localmente

1. Inicia primero el SSS en una terminal.
2. Inicia el cliente en otra terminal:

   ```powershell
   godot --path .
   ```

3. El cliente usa de forma predeterminada `ws://127.0.0.1:9100`.
4. Si el SSS usa otro puerto, cambia el puerto desde la interfaz del cliente antes de conectar.

La guía completa de preparación y solución de problemas está en [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Pruebas

El repositorio contiene pruebas del cliente y del SSS para los hitos M0, M1 y M2. La matriz de comandos y resultados esperados está en [docs/TESTING.md](docs/TESTING.md).

La existencia de una prueba en el repositorio no implica que haya sido ejecutada durante la preparación de esta documentación.

## Documentación

- [Índice de documentación](docs/README.md)
- [Arquitectura](docs/ARCHITECTURE.md)
- [Entorno de desarrollo](docs/DEVELOPMENT.md)
- [Pruebas](docs/TESTING.md)
- [Estado del proyecto](docs/PROJECT_STATUS.md)
- [Contrato WebSocket](contracts/sss_protocol_v1.md)
- [Decisiones abiertas](docs/team3/OPEN_DECISIONS.md)

## Integrantes y roles

> **TODO / PENDIENTE:** confirmar integrantes que deben figurar públicamente y el rol oficial de cada uno.

No se asignan roles a partir de responsabilidades históricas sin confirmación del equipo.

## Metodología de trabajo

> **TODO / PENDIENTE:** confirmar la metodología aplicada actualmente por el equipo antes de publicarla como práctica oficial.

Los materiales académicos existentes describen una metodología propuesta, pero esta documentación no la presenta como definitiva sin validación del equipo.
