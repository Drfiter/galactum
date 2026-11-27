#!/usr/bin/env python3
"""Instala y verifica el "galactum workflow" en un ComfyUI local.

Uso (con ComfyUI corriendo en http://127.0.0.1:8188):
    python install_galactum_workflow.py --comfy-dir RUTA/A/ComfyUI
    python install_galactum_workflow.py --comfy-dir RUTA/A/ComfyUI --download

Qué hace:
  1. Verifica que ComfyUI responda y que existan todos los nodos del workflow
     (son nodos nativos: si falta alguno, hay que actualizar ComfyUI).
  2. Verifica que estén los modelos (y los descarga con --download).
  3. Guarda el workflow como "galactum workflow" en la biblioteca de ComfyUI.
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HERE = Path(__file__).resolve().parent
WORKFLOW_FILE = HERE / "galactum_workflow.json"
WORKFLOW_NAME = "galactum workflow.json"

# carpeta en models/ -> (archivo, url)
MODELS: list[tuple[str, str, str]] = [
    ("vae", "trellis_2_texture_vae_bf16.safetensors",
     "https://huggingface.co/Comfy-Org/Pixal3D/resolve/main/vae/trellis_2_texture_vae_bf16.safetensors"),
    ("vae", "trellis_2_shape_vae_bf16.safetensors",
     "https://huggingface.co/Comfy-Org/Pixal3D/resolve/main/vae/trellis_2_shape_vae_bf16.safetensors"),
    ("clip_vision", "dino_v3_L_naf_fp32.safetensors",
     "https://huggingface.co/Comfy-Org/Pixal3D/resolve/main/clip_vision/dino_v3_L_naf_fp32.safetensors"),
    ("geometry_estimation", "moge_2_vitl_normal_fp16.safetensors",
     "https://huggingface.co/Comfy-Org/MoGe/resolve/main/geometry_estimation/moge_2_vitl_normal_fp16.safetensors"),
    ("background_removal", "birefnet.safetensors",
     "https://huggingface.co/Comfy-Org/BiRefNet/resolve/main/background_removal/birefnet.safetensors"),
    ("diffusion_models", "pixal3d_int8_convrot.safetensors",
     "https://huggingface.co/Comfy-Org/Pixal3D/resolve/main/diffusion_models/pixal3d_int8_convrot.safetensors"),
    ("diffusion_models", "trellis_2_int8_convrot.safetensors",
     "https://huggingface.co/Comfy-Org/TRELLIS.2/resolve/main/diffusion_models/trellis_2_int8_convrot.safetensors"),
]

UI_ONLY_TYPES = {"MarkdownNote", "Note", "PrimitiveInt", "PrimitiveBoolean"}


def http_json(url: str, data: bytes | None = None, method: str = "GET"):
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(req, timeout=30) as r:
        body = r.read()
    return json.loads(body) if body else None


def check_nodes(server: str, workflow: dict) -> bool:
    try:
        info = http_json(f"{server}/object_info")
    except (urllib.error.URLError, OSError) as e:
        print(f"[!] No pude conectar con ComfyUI en {server}: {e}")
        print("    Abre ComfyUI y vuelve a ejecutar (o usa --skip-server).")
        return False
    needed = {n["type"] for n in workflow["nodes"]} - UI_ONLY_TYPES
    missing = sorted(t for t in needed if t not in info)
    if missing:
        print("[!] Faltan nodos en tu ComfyUI:", ", ".join(missing))
        print("    TRELLIS.2/Pixal3D son nativos desde ago-2026: actualiza ComfyUI")
        print("    (git pull + pip install -r requirements.txt, o Update en Desktop/Manager).")
        return False
    print(f"[ok] Los {len(needed)} tipos de nodo existen en ComfyUI.")
    return True


def download(url: str, dest: Path) -> None:
    tmp = dest.with_suffix(dest.suffix + ".part")
    print(f"    descargando {dest.name} ...")
    with urllib.request.urlopen(url, timeout=60) as r, open(tmp, "wb") as f:
        total = int(r.headers.get("Content-Length") or 0)
        done = 0
        while chunk := r.read(8 * 1024 * 1024):
            f.write(chunk)
            done += len(chunk)
            if total:
                print(f"\r    {done * 100 // total:3d}%  {done >> 20} / {total >> 20} MB", end="")
    print()
    tmp.replace(dest)


def check_models(comfy_dir: Path, do_download: bool) -> bool:
    ok = True
    for folder, name, url in MODELS:
        path = comfy_dir / "models" / folder / name
        if path.is_file():
            print(f"[ok] models/{folder}/{name}")
            continue
        if do_download:
            path.parent.mkdir(parents=True, exist_ok=True)
            download(url, path)
        else:
            ok = False
            print(f"[!] Falta models/{folder}/{name}\n      {url}")
    if not ok:
        print("    Ejecuta de nuevo con --download para bajarlos (~14 GB en total).")
    return ok


def install_workflow(server: str | None, comfy_dir: Path | None, workflow: dict) -> bool:
    if server:
        key = urllib.parse.quote(f"workflows/{WORKFLOW_NAME}", safe="")
        try:
            http_json(f"{server}/api/userdata/{key}?overwrite=true&full_info=true",
                      data=json.dumps(workflow).encode(), method="POST")
            print(f"[ok] Guardado en ComfyUI como \"{WORKFLOW_NAME}\" (via API).")
            return True
        except (urllib.error.URLError, OSError) as e:
            print(f"[i] La API no aceptó el workflow ({e}); copiando archivo...")
    if comfy_dir:
        dest = comfy_dir / "user" / "default" / "workflows" / WORKFLOW_NAME
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(WORKFLOW_FILE, dest)
        print(f"[ok] Copiado a {dest}")
        return True
    print("[!] No pude instalar el workflow: pasa --comfy-dir o abre ComfyUI.")
    return False


def ensure_input_image(comfy_dir: Path | None) -> None:
    if not comfy_dir:
        return
    dest = comfy_dir / "input" / "galactum_prop.png"
    if dest.exists():
        return
    url = "https://raw.githubusercontent.com/Comfy-Org/workflow_templates/refs/heads/main/input/viking_wolf_rune_axe.png"
    try:
        dest.parent.mkdir(parents=True, exist_ok=True)
        download(url, dest)
        print("[i] input/galactum_prop.png es una imagen de ejemplo: reemplázala por tu prop.")
    except (urllib.error.URLError, OSError) as e:
        print(f"[i] No pude bajar la imagen de ejemplo ({e}); carga tu imagen en LoadImage.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--comfy-dir", type=Path, help="Carpeta raíz de ComfyUI (la que contiene models/)")
    ap.add_argument("--server", default="http://127.0.0.1:8188")
    ap.add_argument("--download", action="store_true", help="Descargar modelos faltantes")
    ap.add_argument("--skip-server", action="store_true", help="No usar la API de ComfyUI")
    args = ap.parse_args()

    workflow = json.loads(WORKFLOW_FILE.read_text(encoding="utf-8"))
    comfy_dir = args.comfy_dir.resolve() if args.comfy_dir else None
    if comfy_dir and not (comfy_dir / "models").is_dir():
        print(f"[!] {comfy_dir} no parece ComfyUI (no tiene models/).")
        print("    En la versión portable suele ser .../ComfyUI_windows_portable/ComfyUI")
        return 1

    server = None if args.skip_server else args.server.rstrip("/")
    nodes_ok = check_nodes(server, workflow) if server else True
    if server and not nodes_ok:
        server_alive = False
        try:
            http_json(f"{server}/system_stats")
            server_alive = True
        except (urllib.error.URLError, OSError):
            pass
        if not server_alive:
            server = None
    models_ok = check_models(comfy_dir, args.download) if comfy_dir else True
    if not comfy_dir:
        print("[i] Sin --comfy-dir no reviso modelos.")
    installed = install_workflow(server, comfy_dir, workflow)
    ensure_input_image(comfy_dir)

    print()
    if installed and nodes_ok and models_ok:
        print("Listo. En ComfyUI: Workflows -> \"galactum workflow\" (recarga la página con F5).")
        return 0
    print("Revisa los [!] de arriba y vuelve a ejecutar.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
