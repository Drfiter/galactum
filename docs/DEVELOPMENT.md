# Entorno de desarrollo de Galactum

## Requisitos

- Git.
- Godot 4.6.2 estándar para el cliente y el SSS implementados en GDScript.
- Windows, Linux o macOS para desarrollo en PC.
- Puerto TCP `9100` disponible, salvo que se configure otro.

Para Android se requieren adicionalmente las plantillas de exportación de Godot, OpenJDK y Android SDK configurados en el editor. Las rutas locales, keystores y credenciales no deben guardarse en el repositorio.

En esta guía, `godot` representa el ejecutable de Godot 4.6.2. En Windows, si no está agregado a `PATH`, se debe usar la ruta completa del `.exe`.

## Clonar

```powershell
git clone https://github.com/Drfiter/galactum.git
cd galactum
```

El estado activo corresponde a M2. Se debe confirmar con el equipo cuál es la rama de entrega antes de iniciar trabajo nuevo. Durante la preparación de esta guía, la rama de integración activa es `integration/team3-m2`.

## Los dos proyectos Godot

El repositorio no contiene un único proyecto ejecutable:

| Proyecto | Ruta | Propósito |
| --- | --- | --- |
| Cliente | `./project.godot` | Interfaz, réplica del mundo y envío de intenciones. |
| SSS | `./server/sss/project.godot` | Servidor headless y simulación autoritativa. |

Importar la raíz en el administrador de Godot abre el cliente. Si se necesita abrir el SSS en el editor, se debe importar `server/sss/project.godot` como un proyecto separado.

## Abrir el cliente en el editor

```powershell
godot --editor --path .
```

La escena principal configurada es `app/main.tscn`.

## Iniciar el SSS

Desde la raíz del repositorio:

```powershell
godot --headless --path .\server\sss
```

La configuración predeterminada es:

- protocolo `team3-m2.0`;
- puerto `9100`;
- simulación a 2 Hz;
- mapa `600 x 600`.

El proceso informa su disponibilidad mediante una línea `SSS_READY`. La presencia de esa línea por sí sola no reemplaza la ejecución de las pruebas correspondientes.

### Usar otro puerto

Puede definirse mediante argumento:

```powershell
godot --headless --path .\server\sss -- --port=9200
```

También puede usarse la variable de entorno `SSS_PORT`. El cliente debe apuntar al mismo puerto desde su interfaz.

## Ejecutar el cliente

Con el SSS en ejecución, abre otra terminal en la raíz:

```powershell
godot --path .
```

El cliente intenta conectarse de forma predeterminada a:

```text
ws://127.0.0.1:9100
```

La interfaz permite cambiar host y puerto. Desde un dispositivo Android, `127.0.0.1` se refiere al propio dispositivo; para un SSS ejecutado en el PC debe usarse la dirección IPv4 del PC dentro de la red local.

## Flujo local recomendado

1. Comprueba que el puerto elegido esté libre.
2. Inicia el SSS.
3. Inicia el cliente.
4. Conecta con el host y puerto configurados.
5. Comprueba que el cliente reciba un snapshot completo antes de interactuar con el mapa.
6. Para M2, selecciona la nave propia, elige un destino y confirma la intención de viaje.

## Android

La guía [team3/TEAM3-M1-ANDROID.md](team3/TEAM3-M1-ANDROID.md) conserva los pasos históricos de preparación de Android usados en M1. Sus nombres de preset, archivo APK y protocolo todavía no están alineados con M2, por lo que deben revisarse antes de usarlos como procedimiento de entrega actual.

Principios vigentes:

- no versionar rutas del SDK o JDK;
- no versionar keystores ni contraseñas;
- conceder permiso de Internet a la aplicación;
- ejecutar cliente y SSS en la misma red durante pruebas LAN;
- validar background/resume y recuperación de conexión en dispositivo real.

## Archivos generados

Godot genera cachés dentro de `.godot/` para cada proyecto. Esos directorios están ignorados por Git y pueden reconstruirse.

Sí deben versionarse:

- archivos `.uid` asociados a scripts;
- archivos `.import` asociados a recursos importados;
- `export_presets.cfg`, siempre que no contenga secretos.

## Solución de problemas

### El comando godot no existe

Usa la ruta completa del ejecutable de Godot 4.6.2 o agrégala a `PATH`.

### El SSS no puede escuchar

Comprueba si otro proceso está usando el puerto `9100`. Inicia el SSS con otro puerto y configura el mismo valor en el cliente.

### Android no se conecta al PC

Usa la IPv4 LAN del PC, no `127.0.0.1`. Comprueba además el firewall y que ambos dispositivos estén en la misma red.

### Versión de protocolo incompatible

El runtime activo requiere `team3-m2.0` en ambos extremos. Los smoke tests históricos M0 y M1 usan versiones anteriores y no son compatibles con la configuración M2 actual sin un mecanismo de compatibilidad o una actualización posterior.

### El cliente detecta desincronización

La recuperación esperada consiste en solicitar un snapshot completo. Consulta [ARCHITECTURE.md](ARCHITECTURE.md) para el flujo de secuencias y reconstrucción de `WorldState`.
