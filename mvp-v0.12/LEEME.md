# GALACTUM — MVP jugable (v0.12)

Estrategia espacial MMO inspirada en *Lords Mobile*: tu **Astronave** es tu base. Desde ella envías **flotas** para minar asteroides, cazar xenoformas, espiar y saquear a otros comandantes en una **galaxia de Sistemas Solares persistentes de 600×600 casillas**. Idiomas: **inglés (por defecto) y español**. El proyecto es de Godot 4.6, está pensado para **Android** (táctil, horizontal) y también corre en PC.

---

## 1. Ejecutar en PC (Windows)

**Lo más rápido (sin instalar nada):** en el repositorio, abre `releases/windows/Galactum-2026-11-12-v0.12.4-windows.zip`, extrae `Galactum.exe` y haz doble clic. Si Windows muestra «Windows protegió su PC»: *Más información* → *Ejecutar de todas formas* (el ejecutable no tiene firma digital). Incluye JUGAR y JUGAR CON CUENTA.


1. Copia `Godot_v4.6.2-stable_win64.exe` dentro de la carpeta `Godot/` (es el mismo ejecutable de la demo anterior).
2. Doble clic en **`Ejecutar_Galactum.bat`**.
3. En el título escribe tu nombre, elige un retrato y pulsa **JUGAR**.

Ya **no hace falta levantar un servidor aparte**. El servidor autoritativo (SGM + SSS) corre *embebido* dentro del juego, que es lo que permite jugarlo sin red en un teléfono. El progreso se guarda solo (cada 45 s, al salir y al minimizar en Android).

Otros lanzadores:

| Archivo | Para qué |
|---|---|
| `Ejecutar_Servidor_Dedicado.bat [puerto]` | SSS dedicado headless por WebSocket (por defecto, puerto 9100) |
| `docker compose up -d --build` | SSS dedicado + versión web en http://localhost:8080 (ver sección 4.2) |
| `Ejecutar_Demo_2_Clientes.bat` | Levanta el SSS y abre 2 clientes. En cada uno: *Servidor dedicado* → `127.0.0.1:9100` → usuario y contraseña → *Crear cuenta* (la primera vez) o *Entrar*, con usuarios distintos |
| `Abrir_en_Editor.bat` | Abre el proyecto en el editor (también sirve para exportar a Android) |
| `Ejecutar_Pruebas.bat` | Suite de pruebas canónicas + harness de balance de 10.000 combates |

Desde el editor: abre `project.godot` y pulsa **F5**.

---

## 2. Cómo se juega

- **NAVE** (botón redondo, abajo a la izquierda): tus 12 salas. Tócalas para mejorarlas. Las salas productoras muestran una **burbuja verde**; tócala para recolectar.
- **MAPA**: arrastra para moverte, pellizca o usa la rueda para el zoom, y toca algo para ver su ficha:
  - **Asteroide** → *Minar*: la flota viaja, extrae (solo una flota a la vez) y vuelve con la carga.
  - **Xenoforma** → *Cazar*: cuesta Energía. Cada especie es débil al daño **físico** (Infantería, Escudos, Cañoneros) o **energético** (Drones, Pilotos). Su vida persiste entre ataques.
  - **Nave enemiga** → *Espiar* / *Atacar*. Si ganas, saqueas lo que exceda su Bóveda Cuántica.
  - **Flota minera enemiga** sobre un asteroide → *Atacar flota minera* (tile hitting).
  - **Espacio vacío** → *Mover Astronave aquí* (cuesta Plasma; la nave queda TRAVELING) o *Salto Warp*.
- **Combate**: triángulo Infantería > Drones > Pilotos > Infantería (+30%). Los Escudos absorben primero y los Cañoneros rompen Escudos y el Escudo Perimetral. Los heridos van a la **Bahía Médica**; de las bajas mortales, el 80% va al **Criosantuario** y el 20% se pierde.
- **Comandantes bot**: minan, cazan, pelean entre ellos y **te atacan**. Antes de cada ataque recibes una alerta roja con cuenta atrás y la opción de activar un Campo de Distorsión.
- **Misiones** (tarjeta de la izquierda): 12 misiones de historia que enseñan el bucle, más el evento rotativo **Órdenes del Día**.
- **Alianza**: chat, **Ayuda Mutua** (acelera temporizadores) y **Cápsulas de Suministro** (se generan cuando un miembro caza).

### Novedades v0.10-0.12 (feedback de la revisión)

| Feedback | Dónde está en el juego |
|---|---|
| Más de un sistema / saltar entre sistemas (otro servidor) · 10 sistemas + 1 por mes | **Galaxia** (menú inferior o tocando el Portal de Salto): 16 sistemas, cada uno con su mapa, bots y nebulosa. Los nuevos comandantes nacen en el más nuevo; los veteranos esperan 180 días para entrar a un sistema nuevo. Salto con *Motor de Salto Interestelar* (desde cualquier punto) o por el *Portal* (Plasma, si estás a ≤40 casillas). |
| Pertenecer a la misma alianza al saltar | La alianza es global: al saltar sigues en ella (Alianza → Miembros muestra el sistema de cada uno). |
| Salto de escape a un lugar aleatorio | Objeto **Salto de Emergencia**: botón *Escapar* en la alerta de ataque y en la ficha de tu nave. Las flotas enemigas pierden tu rastro. |
| Inglés + selector de idioma | Inglés por defecto; selector en el título y en *Menú*. Textos en `data/i18n_en.json`. |
| Lista de elementos con precio / moneda opaca | **Tienda → Tabla de precios** y la planilla `Galactum_Tabla_de_Precios.xlsx`. 1 USD = 100 Materia Oscura; todo tiene valor en MO (`data/catalog_shop.json`). Compras con dinero simuladas. |
| Bono de login cada 24 h | **Bono** (botón verde a la izquierda): caja aleatoria de ≈ US$1 por día; el día 7 vale US$3 + Salto Warp. |
| Premios e incentivos para el grupo, "caza 5 bichos al día", "ataquemos entre todos a tal nave" | **Alianza → Metas y Cofre**: metas diarias grupales, cuota por miembro, cofre bronce/plata/oro, nivel de alianza con bonos. **Objetivo**: marca una nave enemiga y los aliados la atacan en oleadas (+120 PA por golpe). **Ranking** de alianzas. |
| Eventos con bonus de recursos y probar qué tan rentables son | **Eventos** (botón dorado): evento de recursos rotativo (1 h) y torneo rotativo (3 h) con pozo en USD. **Rentabilidad**: valor quemado vs. pozo y ajuste automático del premio, más un simulador. |
| Dos etapas de la nave | Las salas de **Fase 2** (Cantina, Gestión de Tripulación, Armería, Taller de Piezas) se compran y construyen: aparecen como obras con "Construir". |
| Selección de tripulación / reclutar tripulantes | **Tripul.** (botón morado): 45 tripulantes con rareza y pasivas, tripulación activa, reclutamiento x1/x10 y gratis diario en la Cantina. |
| Gráfica de combate más vistosa | Explosiones con escombros, humo, láseres y vibración de cámara en el mapa. **Informes → Ver batalla en 3D**: repetición ronda a ronda. |

Para la presentación hay botones **"Demo: …"** (simular el siguiente día del bono o de la alianza, terminar un torneo, pasar de evento, provocar una incursión).

---

### Correcciones v0.12.2 (feedback del 26/10/2026)

Informe completo con evidencias: `docs/Informe_correcciones_feedback_2026-11-09.pdf` (en la raíz del repositorio).
Estado de todo el feedback (qué se hizo, qué está parcial, qué falta y de qué equipo es): `docs/Estado_feedback_2026-11-09.pdf`.

| Error reportado | Arreglo |
|---|---|
| El botón Cazar/Minar de la tarjeta a veces no respondía o el toque caía en "Informes" | La tarjeta ya no se reconstruye mientras el dedo está encima; la barra inferior espera 450 ms antes de reaparecer y la tarjeta respeta la barra de gestos de Android. |
| Las coordenadas no cambiaban tras reubicar la nave | La cámara acompaña a la Astronave al llegar (viaje, Salto Warp o Salto de Emergencia). |
| Aviso con el estado interno "(TRAVELING)" | Texto corregido en español e inglés. |
| Etiquetas de salas tapadas por la barra de colas | La cubierta se encuadra sola entre la barra de colas, el menú inferior y la tarjeta de misiones, en cualquier formato de pantalla. |
| El chat de alianza parecía mostrar combates de otras alianzas | Ambos bandos aparecen con su etiqueta: "[VGA] Velux fue repelido por [VOI] Kelux". |
| Sin audio | 9 efectos y música ambiental generados por síntesis (`tools/gen_audio.py`), con interruptores de Música y Efectos en el Menú. |
| Un bot se llamaba "Comandante Kael", como el tripulante n.º 1 | El aliado inicial ahora es "Comandante Arvel"; las partidas guardadas antiguas se corrigen al cargar. |

### Correcciones v0.12.1

| Problema | Arreglo |
|---|---|
| Los números salían con formato español en inglés ("1.500", "20.000") | `fmt_int` y `fmt_num` usan el separador del idioma activo: "1,500" / "1.5K" en inglés, "1.500" / "1,5K" en español. |
| Los nombres 3D de salas y entidades se transparentaban sobre la cola de construcción, la tarjeta de misiones y la barra de recursos | Fondos del HUD (`Chip` y `TopBar`) opacos. |
| Al abrir un clon limpio Godot mostraba errores al cargar `Exo2.ttf` | Se quitó la fuente global de `project.godot`; el tema de `ui/ui.gd` ya la asigna en tiempo de ejecución. |

---

## 3. Guion de demo (≈5 min, para la presentación)

1. **Título** → nombre y retrato → JUGAR. Comenta que el servidor autoritativo corre embebido y que el mismo juego puede conectarse a un SSS dedicado.
   - **Cuentas y JWT (1 min):** en el título pulsa **JUGAR CON CUENTA** → escribe usuario y contraseña → *Crear cuenta*. El panel muestra la contraseña cifrada (PBKDF2), el token JWT firmado (sus 3 partes y su contenido) y la validación al entrar. Pulsa **Probar token alterado**: el servidor lo rechaza («Token inválido o vencido»). Luego **ENTRAR AL JUEGO**. Para mostrar un error, vuelve al título y usa *Entrar* con una contraseña incorrecta. No necesita red: usa el servidor embebido en modo «exige cuenta» y guarda las cuentas en `user://galactum_cuentas.json`.
2. **Nave**: recolecta una burbuja verde → reclama la misión 1 → mejora la Fábrica → pulsa **Ayuda** (los aliados reducen el temporizador en vivo).
3. **Hangar**: entrena 30 unidades. Muestra el triángulo y los stats de cada fuerza.
4. **Mapa**: toca un asteroide → *Minar* → muestra la ruta, el anillo de progreso de la extracción y el regreso con la carga (misión 6).
5. **Caza**: toca una xenoforma → *Cazar* con la composición *Recomendada* → abre el informe (daño, debilidad, heridos, recompensas, cápsula para la alianza).
6. **PvP**: espía a un rival novato (informe con precisión según la Sala de Sensores) → atácalo → efecto de combate → informe por rondas con botín, heridos/criostasis/perdidos, `combat_version` y `seed` (replay determinista).
7. **Defensa**: Menú → *Demo: provocar incursión enemiga* → alerta roja con cuenta atrás → informe de defensa con el Escudo Perimetral.
8. **Viaje**: toca un espacio vacío → *Mover Astronave aquí* (estado TRAVELING; no produce ni puede ser atacada).
9. (Opcional) **Multijugador**: `Ejecutar_Demo_2_Clientes.bat`. Los dos comandantes aparecen como vecinos y pueden espiarse y atacarse.

**Demo del feedback (≈5 min extra):**

10. **Bono diario** (se abre solo al entrar) → reclamar → *Demo: simular siguiente día*.
11. **Tienda** → *Tabla de precios* (moneda opaca) → *Materia Oscura* (compra simulada).
12. **Alianza → Metas y Cofre** (metas grupales, cuota, cofre) → **Mapa**: toca una nave enemiga → *Marcar objetivo* → los aliados salen a atacarla.
13. **Eventos** → torneo y clasificación → *Demo: terminar torneo* → *Rentabilidad*.
14. **Nave** → toca *Cantina (Construir)* → construir → **Tripul.** → *Reclutar ×10* → activar tripulantes.
15. **Informes** → un ataque → *Ver batalla en 3D*.
16. **Galaxia** → elige un sistema → *Usar Motor de Salto Interestelar* (transición de hiperespacio). Alerta de ataque → *Escapar* (Salto de Emergencia).
17. **Menú** → idioma English/Español.

---

## 3.1 Mostrar el código de cuentas y JWT en VS Code

Abre la carpeta `mvp-v0.12` en Visual Studio Code; te sugerirá la extensión **godot-tools** (colores de GDScript). Recorrido sugerido, en este orden:

| Archivo | Qué mostrar |
|---|---|
| `server/net/auth.gd` | `register()` y `login()`; `pbkdf2()` (la contraseña se guarda con sal y hash); `jwt_sign()` y `jwt_verify()` (firma HS256 y vencimiento); `refresh()` (rotación del token de renovación) |
| `server/game_server.gd` | `_on_auth()` recibe registro/login; `_on_hello()` valida el JWT antes de dejar entrar (`AUTH_REQUIRED` / `AUTH_INVALID_TOKEN`) |
| `client/game_client.gd` | `start_local_accounts()`, `_on_auth()` y `decode_jwt()` |
| `ui/account_demo.gd` | El panel «Jugar con cuenta», la prueba de token alterado y «Ver datos guardados» |
| `tests/features_checks.gd` | `test_accounts()`: 21 comprobaciones automáticas |

**Datos guardados en vivo:** abre también en VS Code el archivo `galactum_cuentas.json` (Windows: `%APPDATA%\Godot\app_userdata\Galactum\`). Al pulsar *Crear cuenta*, VS Code lo recarga solo y aparece la cuenta nueva con su `salt` y `hash`, sin la contraseña.

## 4. Exportar a Android (APK)

**Instalar el APK ya compilado:** el más reciente es `releases/android/Galactum-2026-11-10-v0.12.3.apk` (v0.12.3, con todo lo de noviembre). Si tienes instalada la versión del 25/10, desinstálala primero: el APK nuevo está firmado con otra clave. Cópialo al teléfono (o descárgalo directo en él), ábrelo y, cuando Android lo pida, permite *Instalar apps desconocidas* para esa app (Archivos/Chrome). Requiere Android 7.0+ (ARM 32/64 bits). Se juega en horizontal y sin conexión.

**Exportarlo tú mismo:**

Una sola vez:

1. Instala **JDK 17** y **Android Studio** (o solo las *command line tools*). Desde el SDK Manager instala: *Android SDK Platform-Tools*, *Build-Tools 34+* y *Platform 34+*.
2. En Godot: **Editor → Gestionar plantillas de exportación → Descargar e instalar** (4.6.2).
3. En Godot: **Editor → Configuración del editor → Exportar → Android**: rellena *Java SDK Path* y *Android SDK Path*. El keystore de depuración se genera solo.

Para exportar:

4. **Proyecto → Exportar…** → preset **Android** (ya está configurado: paquete `cl.duocuc.galactum`, arm64 + armv7, orientación horizontal, inmersivo, íconos, permiso INTERNET para el modo dedicado).
5. **Exportar proyecto** → `build/android/Galactum.apk`. Con el teléfono conectado en modo depuración USB también puedes usar el botón ▶ Android del editor (despliegue en un clic).

Para publicar en la tienda, crea un keystore de release y configúralo en el preset (*Keystore → Release*).

Con el teléfono y el PC en la misma red Wi-Fi puedes conectar el APK al servidor dedicado: *Servidor dedicado* → IP del PC → puerto 9100 → usuario y contraseña.

### Cuentas en el servidor dedicado

El SSS dedicado exige una cuenta: registro e inicio de sesión con usuario y contraseña, token de acceso **JWT HS256** (15 min) que el `hello` debe presentar, y token de renovación de un solo uso (30 días, rotación y revocación al cerrar sesión). Las contraseñas se guardan con **PBKDF2-HMAC-SHA256** y sal por cuenta; tras 5 intentos fallidos la cuenta se bloquea 5 minutos.

- Define `GALACTUM_JWT_SECRET` (32 caracteres o más) en el entorno del servidor. Si falta, se usa un secreto aleatorio por proceso y los tokens de acceso dejan de valer al reiniciar (los de renovación siguen sirviendo). **Nunca** lo guardes en el repositorio.
- `-- --server --no-auth` vuelve al modo demo por nombre. La partida local (JUGAR) no usa cuentas.
- Alcance MVP: no hay NestJS/PostgreSQL ni recuperación de contraseña; las iteraciones de PBKDF2 son pocas porque corre en GDScript (en producción iría Argon2/bcrypt en el backend del Equipo 1).

---

## 4.1 Apartado visual 3D (v0.9)

- **Mapa y Astronave en 3D** con cámara isométrica en perspectiva (estilo *Clash of Clans*): modelos low-poly procedurales (`ui/world3d/mesh_kit.gd`), sombreado *toon* con borde (`assets/shaders/toon.gdshader` + `outline.gdshader`), suelo holográfico con nebulosa, sombras de contacto, anillos y rutas animadas.
- **Astronave**: cada sala es un edificio 3D propio sobre la cubierta; las obras de Fase 2 se ven como andamios. Toca un edificio para abrirlo y las burbujas verdes para recolectar.
- **Interfaz** con tipografía *Lilita One* (OFL) y botones gruesos con relieve.
- Renderer *Compatibility* (OpenGL ES 3) para funcionar en la mayoría de teléfonos.

## 4.2 Docker (servidor dedicado + versión web)

Levanta el SSS dedicado y el cliente web (HTML5/WebAssembly servido por nginx) con un solo comando. Solo necesitas **Docker Desktop**; no hace falta instalar Godot.

```powershell
cd mvp-v0.12
copy .env.example .env          # y completa GALACTUM_JWT_SECRET (32+ caracteres)
docker compose up -d --build
docker compose ps               # server debe quedar "healthy"
```

Abre **http://localhost:8080** → *Servidor dedicado* (la dirección `ws://localhost:8080/ws` se completa sola) → usuario y contraseña → *Crear cuenta* la primera vez y luego *Entrar*. Los clientes de escritorio o Android pueden conectarse directo a `127.0.0.1:9100`.

| Servicio | Imagen | Qué hace |
|---|---|---|
| `server` | `galactum-server:0.12` | Godot 4.6.2 headless: SSS autoritativo por WebSocket (9100), cuentas JWT y guardado en el volumen `galactum-data` (`/data/godot/app_userdata/Galactum/galactum_server_save.json`). Healthcheck: handshake WebSocket (`docker/healthcheck.py`). |
| `web` | `galactum-web:0.12` | nginx sirve la exportación web y reenvía `/ws` al servidor. Arranca cuando `server` está sano. |

Archivos: `compose.yaml`, `docker/Dockerfile` (etapas `base`, `server`, `webexp`, `web`), `docker/nginx.conf`, `docker/healthcheck.py`, `.env.example`. La primera construcción descarga Godot (~70 MB) y sus plantillas de exportación (~1,2 GB, de las que solo se conservan las web); las siguientes usan la caché.

Operación habitual:

```powershell
docker compose logs --tail 100 server   # "Estado restaurado…", "SSS WebSocket escuchando en el puerto 9100"
docker compose stop ; docker compose start
docker compose down                     # borra contenedores; el volumen (y las cuentas) se conservan
docker compose down -v                  # borra también el volumen: mundo y cuentas desde cero
```

Verificado el 10/11/2026: construcción de ambas imágenes, servidor *healthy*, registro e inicio de sesión a través de nginx (`/ws`), rechazo sin cuenta, restauración del estado y de las cuentas tras `down`/`up`, y el juego completo en Chromium (WebGL 2) desde `http://localhost:8080`. Pendiente para publicar fuera del PC: HTTPS (proxy con certificado delante de nginx; el cliente usa `wss://` automáticamente).

---

## 5. Arquitectura (cómo se reparte el trabajo de los 5 equipos)

```
app/boot.gd            Punto de entrada: --server = SSS dedicado; si no, título
shared/                Catálogos (autoload Catalog) y utilidades puras
data/*.json            TODO el balance: tropas, salas, investigación, xenoformas,
                       asteroides, items, misiones, mundo (sin números en código)
server/                SERVIDOR AUTORITATIVO (el cliente solo envía intenciones)
  game_server.gd         sesiones, tick 2 Hz, replicación AOI, despacho de intenciones, snapshots
  sgm/economy.gd         Equipo 1/2: ledger con idempotencia y rollback, producción lazy, modificadores
  sgm/progression.gd     Equipo 2: mejoras de sala, investigación, entrenamiento, curación, criostasis, aceleradores
  sgm/missions.gd        Equipo 5: misiones y evento «Órdenes del Día» data-driven
  social.gd              Equipo 4: alianzas, chat, Ayuda Mutua, Cápsulas de Suministro
  reports.gd             battle_reports por bando
  sss/world.gd           Equipo 3: mapa 600×600, terreno, asteroides N1-N5, xenoformas, respawn
  sss/spatial_hash.gd    índice espacial para las consultas AOI
  sss/fleets.gd          Equipo 3: marchas (minar/cazar/atacar/espiar), tile hitting, viaje ANCHORED→TRAVELING
  sss/bots.gd            comandantes IA (y bots para el soak test)
  combat/combat_resolver.gd  resolver DETERMINISTA, PURO y VERSIONADO (Equipo 3 §7)
  net/ws_gateway.gd      gateway WebSocket del modo dedicado
  net/auth.gd            cuentas: registro, login, JWT HS256 y renovación
client/                Réplica no autoritativa + enlaces (local en memoria / WebSocket)
ui/                    Título, mapa, interior de la nave, HUD y ventanas
  audio.gd               efectos y música del cliente (nodo creado a demanda, no Autoload)
tests/, tools/         Pruebas canónicas, prueba de humo, harness de balance
```

**Protocolo** (JSON, igual en modo local y en WebSocket):

- Cliente → servidor: `hello`, `view` (centro y radio de la cámara, para el AOI), `intent` (`march`, `recall`, `relocate`, `upgrade_room`, `research`, `train`, `heal`, `revive`, `speedup`, `help`, `collect`, `use_item`, `claim_mission`, `claim_daily`, `open_capsules`, `chat`…).
- Servidor → cliente: `welcome`, `player`, `map_delta` (`added` / `updated` / `removed` según el área de interés), `report`, `toast`, `chat`, `fx`, `ack` / `error` (con `request_id`).

Decisiones de la spec que se respetan:

- Las flotas se modelan como (origen, destino, `depart_ts`, `arrive_ts`) y la posición se **deriva del tiempo**. Por eso los vuelos sobreviven a reinicios.
- La carga se abona con una clave de idempotencia del viaje.
- Cada combate guarda `combat_version` y `seed`.

---

## 6. Pruebas y balance

```
godot --headless --path . res://tests/run_tests.tscn          # 24 pruebas canónicas
godot --headless --path . res://tests/server_smoke.tscn       # bucle completo: minería, caza, PvP, galaxia, alianza, torneos, tripulación
godot --headless --path . res://tests/feedback_checks.tscn    # 24 comprobaciones de los errores del feedback del 26/10
godot --headless --path . res://tests/features_checks.tscn    # 204 comprobaciones de las funcionalidades agregadas (fases 1-9)
godot --headless --path . res://tools/balance_harness.tscn -- --n=10000
```

Resultado actual del harness (10.000 combates por matchup, «espejo + ventaja», escalones N1 a N5): **Infantería > Drones 68,1–70,2%**, **Drones > Pilotos 63,8–68,1%**, **Pilotos > Infantería 61,9–65,7%**. Los 15 matchups quedan dentro del rango 60–75% que exige la spec. Para lograrlo se rebalanceó el escalón N2 (antes Pilotos > Infantería quedaba en 51%): todos los escalones derivan de N1 con multiplicadores enteros y defensa constante. El CSV se guarda en `user://balance_report.csv`.

Para rebalancear, edita `data/catalog_troops.json` y vuelve a correr el harness.

---

## 7. Alcance del MVP y lo que viene

**Incluido:** 24 salas (Puente hasta Nv 25), los 10 elementos + 4 monedas y los Bonos de Alianza, las 5 fuerzas (N1-N5) con 5 formaciones, árbol de investigación de 5 ramas y 30 tecnologías, minería, caza PvE de 24 especies × 5 niveles, PvP contra naves y flotas, espionaje, viaje y Salto Warp, Bahía Médica, Criosantuario 80/20, Bóveda, Escudo Perimetral, alianza con ayuda, chat y cápsulas, misiones, Órdenes del Día, inventario, informes, guardado y servidor dedicado.

**Ya incluido de la Fase 2:** galaxia multisistema con salto interestelar, tienda con moneda opaca, bono diario, dinámicas de alianza (metas, cofre, objetivo marcado, ranking), eventos y torneos con métricas de rentabilidad, Cantina y los 45 Tripulantes, Gestión de Tripulación, Armería, Taller (canje), visor de batallas 3D, inglés/español.

**Agregado tras el feedback del 26/10 (noviembre 2026):** Tripulantes en las flotas (hasta 5, Insignias, grados, rangos y doble empleo); Comandante (nivel, Protocolos de Mando y captura); Armería con 150 materiales y 90 equipos × 5 niveles; Alianzas completas (crear, buscar, unirse, R1-R5, Tesorería, Tienda, Bonos), Asedio (rally) y refuerzos; Pase de Expedición, Licencia de Comandante, Eventos de Singularidad y Festival de la Flota; Expediciones (6 capítulos × 8 etapas, Élite y barrido); Colmenas Xeno, Plataformas Orbitales, títulos y Operación de Rescate (30%); cuentas con JWT en el servidor dedicado. Detalle y evidencias: `docs/Informe_funcionalidades_feedback_2026-11-10.pdf`.

**Pendiente:** pagos reales (Google Play Billing requiere una cuenta de Play Console; hoy las compras son simuladas con Materia Oscura), el SGM en NestJS + PostgreSQL del Equipo 1, recuperación de contraseña, backoffice y Guerra de Sistemas entre servidores. Las piezas de backend de los Equipos 1, 2, 4 y 5 en NestJS siguen en sus carpetas de documentación. Este MVP implementa sus reglas dentro del servidor embebido para poder mostrarlas jugando.

> Nota de demo: los tiempos están acelerados (viajes de segundos, mejoras de 15 s a minutos) para mostrar el bucle completo en una presentación. Todos esos valores están en `data/*.json`.

---

*Galactum · Proyecto de Título (APT) · Duoc UC 2026. El arte es el catálogo placeholder vectorial del proyecto. Fuentes Exo 2, Orbitron y Lilita One (SIL Open Font License, en `assets/fonts`). El audio es síntesis propia (`tools/gen_audio.py`), sin archivos de terceros.*
