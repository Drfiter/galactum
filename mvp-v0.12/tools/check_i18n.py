#!/usr/bin/env python3
"""Lista los textos U.t("...") del código que no tienen traducción al inglés.

Uso:  python3 tools/check_i18n.py            (muestra los faltantes)
      python3 tools/check_i18n.py --json     (los imprime como plantilla JSON)
Sale con código 1 si falta alguno.
"""
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
PAT = re.compile(r'U\.t\("((?:[^"\\]|\\.)*)"\)')
DATA_KEYS = ("name", "desc", "title", "phase", "short", "label")


def code_strings():
    found = {}
    for base in ("server", "ui", "shared", "client", "app"):
        for dirpath, _dirs, files in os.walk(os.path.join(ROOT, base)):
            for fn in files:
                if fn.endswith(".gd"):
                    path = os.path.join(dirpath, fn)
                    for m in PAT.finditer(open(path, encoding="utf-8").read()):
                        text = bytes(m.group(1), "utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8")
                        found.setdefault(text, os.path.relpath(path, ROOT))
    return found


def main():
    tr = json.load(open(os.path.join(ROOT, "data", "i18n_en.json"), encoding="utf-8"))
    missing = {k: v for k, v in code_strings().items() if k and k not in tr}
    if "--json" in sys.argv:
        print(json.dumps({k: "" for k in missing}, ensure_ascii=False, indent=1))
    else:
        for k, where in sorted(missing.items(), key=lambda kv: kv[1]):
            print(f"{where}: {k}")
        print(f"{len(missing)} textos sin traducción")
    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    main()
