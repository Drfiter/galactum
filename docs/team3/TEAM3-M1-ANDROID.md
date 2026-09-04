# TEAM3-M1 — Ejecución en Android real

Esta guía documenta cómo ejecutar el cliente Galactum (Equipo 3) en un
dispositivo Android físico, conectado por WebSocket al SSS headless en un PC de
la misma red.

> El objetivo es conseguir:
> ```
> PC └── SSS headless (puerto 9100)
>            ↑ Wi-Fi / WebSocket ws://
> Android └── Cliente Galactum
> ```

No se versionan rutas de SDK/JDK, IPs de PC, keystores ni credenciales.
Cualquier ajuste dependiente de la máquina se hace en el editor de Godot y se
documenta aquí (no se sube).

---

## 1. Requisitos previos en el PC

| Herramienta | Requisito | Notas |
|:---|:---|:---|
| Godot 4.6 | Editor + **Export Templates de Android** | Instalar desde el Editor: `Editor → Manage Export Templates → Download and Install`. |
| OpenJDK 17 | JDK 17 (no 11 ni 21 en algunas versiones) | Ruta configurada en el Editor: `Editor Settings → Export → Android → Java SDK Path`. |
| Android SDK | `platform-tools`, `platforms;android-XX`, `build-tools`, `cmdline-tools` | Ruta en `Editor Settings → Export → Android → Android SDK Path`. |
| ADB | Parte del Android SDK (`platform-tools`) | Para instalar el APK y depurar. |

> Estas son las rutas que **se configuran localmente en tu máquina**; NO se
> versionan. Los presets del repo (`export_presets.cfg`) no contienen rutas
> absolutas del equipo.

## 2. Keystore de firma (local, no versionado)

1. En el Editor: `Project → Export → Android`.
2. Pestaña **Options → Keystore**.
3. **Debug**: usa el keystore de debug generado automáticamente por Godot
   (recomendado para pruebas). Si quieres un keystore propio:
   - `keytool -genkey -v -keystore galactum-debug.keystore -alias galactum -keyalg RSA -keysize 2048 -validity 10000`.
   - Registra su ruta y password **solo en tu máquina**.
4. Revisa que `permissions/internet=true` estén marcadas (ya está en el preset
   `Android (TEAM3-M0)`).

## 3. Preparar el SSS en el PC

Abrir un firewall para el puerto del SSS solo en la red privada (de ser
necesario) y arrancar el servidor:

```powershell
# En la raíz del repo
godot --headless --path .\server\sss
```

Para otro puerto:

```powershell
godot --headless --path .\server\sss -- --port=9200
```

Verás la línea `SSS_READY protocol=team3-m0.1 port=9100 tick_hz=2.0 system_id=...`.

## 4. Obtener la IP LAN del PC

```powershell
ipconfig
```

Usa la **IPv4 de la interfaz Wi-Fi/LAN** del PC (ej. `192.168.1.50`).
**NO uses `127.0.0.1` desde Android** (apunta al propio teléfono, no al PC).

## 5. Build / instalación en Android

Opción A — build y run desde el editor (con dispositivo por USB/ADB):

1. Conecta el teléfono por USB con depuración habilitada.
2. En el Editor: `Project → Export → Android → Export Project` (genera
   `builds/android/galactum-team3-m0.apk`).
3. Instala: `adb install -r builds/android/galactum-team3-m0.apk`.

Opción B — export directo al dispositivo:

1. En la ventana de Export, selecciona **Android + dispositivo** y pulsa
   **Export and Run**.

## 6. Conexión del cliente

1. PC y teléfono en la **misma red Wi-Fi/LAN**.
2. Inicia el SSS en el PC (paso 3).
3. Abre la app Galactum en Android.
4. En el campo **Host** escribe la **IPv4 LAN del PC** (no `127.0.0.1`).
5. Pulsa **Conectar**.
6. Verifica en pantalla: autenticación mock aceptada, `full_snapshot` aplicado,
   protocol/seq/server_time, la nave dummy, y luego latencia `ping ms`.

## 7. Pruebas manuales recomendadas en Android

- [ ] Conexión a `ws://<IP LAN>:9100` y vista del mapa 600×600.
- [ ] Paneo (arrastrar un dedo) y zoom (pellizco) de la vista diagnóstica.
- [ ] Toque sobre una entidad: se selecciona y se muestra el detalle en la
      etiqueta de selección (sin emitir órdenes de movimiento).
- [ ] **Background/resume**: pulsa el botón Home, espera unos segundos, vuelve a
      la app → debe reconectarse y re-sincronizar (full_snapshot).
- [ ] **Pérdida de red**: apaga/reactivando Wi-Fi → el cliente reconecta y
      solicita full_snapshot.
- [ ] Distintas resoluciones/aspect ratios: verifica que la UI se adapta y la
      vista del mundo sigue operable.

## 8. Notas de integración (coordinadas con el SSS)

- El contrato compartido define `team3-m1.0` como la versión objetivo de M1.
- El **runtime actual** del cliente (`SssConnection`) sigue hablando
  `team3-m0.1` y el SSS de M0 emite `team3-m0.1`, para no romper TEAM3-M0.
- La validación de continuidad de `seq` se hace en el cliente sobre todos los
  mensajes del SSS; ante un gap solicita `full_snapshot`.
- No se implementa `subscribe_area` en M1: el SSS calcula el Área de Interés y
  el cliente solo refleja `added`/`updated`/`removed`. `removed` significa
  "ya no pertenece a la réplica visible", no necesariamente destrucción.
