# syntax=docker/dockerfile:1
# Galactum MVP v0.12 — imágenes del servidor (SSS dedicado) y del cliente web.
# Se construye desde mvp-v0.12/ con `docker compose build` (ver compose.yaml).
#
#   base   : Godot 4.6.2 (Linux, headless) + proyecto importado
#   server : SSS dedicado por WebSocket (puerto 9100), estado en /data
#   webexp : exporta el cliente a HTML5/WebAssembly (solo plantillas web)
#   web    : nginx sirve el cliente y reenvía /ws al servidor

ARG GODOT_VERSION=4.6.2
ARG GODOT_URL=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip
ARG TEMPLATES_URL=https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/Godot_v${GODOT_VERSION}-stable_export_templates.tpz

# ------------------------------------------------------------------ base
FROM python:3.12-slim-bookworm AS base
ARG GODOT_VERSION
ARG GODOT_URL
# Descarga y descomprime Godot con Python (sin instalar paquetes del sistema).
RUN python3 - <<PY
import io, os, stat, urllib.request, zipfile
data = urllib.request.urlopen("${GODOT_URL}").read()
with zipfile.ZipFile(io.BytesIO(data)) as z:
    name = [n for n in z.namelist() if n.endswith(".x86_64")][0]
    with open("/usr/local/bin/godot", "wb") as f:
        f.write(z.read(name))
os.chmod("/usr/local/bin/godot", 0o755)
PY
WORKDIR /app
COPY . /app
# Importa los recursos una vez (genera .godot/ dentro de la imagen).
RUN godot --headless --path /app --import >/dev/null 2>&1 || true \
 && test -d /app/.godot/imported

# ------------------------------------------------------------------ server
FROM base AS server
# user:// del servidor queda en /data/godot/app_userdata/Galactum (volumen).
ENV XDG_DATA_HOME=/data \
    SSS_PORT=9100
RUN useradd --system --uid 10001 --home-dir /data galactum \
 && mkdir -p /data && chown -R galactum:galactum /data
COPY docker/healthcheck.py /usr/local/bin/healthcheck.py
USER galactum
VOLUME ["/data"]
EXPOSE 9100
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=6 \
  CMD ["python3", "/usr/local/bin/healthcheck.py"]
# GALACTUM_JWT_SECRET llega por el entorno (compose lo lee de .env).
CMD ["godot", "--headless", "--path", "/app", "--", "--server"]

# ------------------------------------------------------------------ webexp
FROM base AS webexp
ARG GODOT_VERSION
ARG TEMPLATES_URL
# De las plantillas (1,2 GB) solo se guardan las dos de web sin hilos.
RUN python3 - <<PY
import os, shutil, urllib.request, zipfile
dest = os.path.expanduser("~/.local/share/godot/export_templates/${GODOT_VERSION}.stable")
os.makedirs(dest, exist_ok=True)
tmp = "/tmp/templates.tpz"
with urllib.request.urlopen("${TEMPLATES_URL}") as r, open(tmp, "wb") as f:
    shutil.copyfileobj(r, f, 1 << 20)
with zipfile.ZipFile(tmp) as z:
    for n in z.namelist():
        base = os.path.basename(n)
        if base in ("version.txt", "web_nothreads_release.zip", "web_nothreads_debug.zip"):
            with open(os.path.join(dest, base), "wb") as out:
                out.write(z.read(n))
os.remove(tmp)
print(sorted(os.listdir(dest)))
PY
RUN mkdir -p /app/build/web \
 && godot --headless --path /app --export-release "Web" /app/build/web/index.html \
 && test -f /app/build/web/index.wasm && test -f /app/build/web/index.pck

# ------------------------------------------------------------------ web
FROM nginx:1.27-alpine AS web
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=webexp /app/build/web/ /usr/share/nginx/html/
EXPOSE 80
