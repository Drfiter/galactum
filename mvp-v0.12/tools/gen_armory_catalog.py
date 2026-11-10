#!/usr/bin/env python3
"""Genera data/catalog_armory.json: 150 materiales y 90 equipos de la Armería.

- Materiales: 30 tipos × 5 calidades = 150. 24 tipos salen de las xenoformas
  (uno por especie, al cazarlas) y 6 son de forja (salen de los asteroides).
- Equipos: 15 conjuntos × 6 ranuras = 90 piezas, cada una mejorable hasta el
  nivel 5. El conjunto define el escalón (1-5); el escalón máximo que se puede
  forjar depende del nivel de la Armería.

Uso:  python3 tools/gen_armory_catalog.py
Los valores de balance están arriba en constantes para ajustarlos fácilmente.
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

GRADES = [
    {"grade": 1, "suffix": "I", "quality": "Común", "color": "#9aa6c8"},
    {"grade": 2, "suffix": "II", "quality": "Refinado", "color": "#5ce08a"},
    {"grade": 3, "suffix": "III", "quality": "Superior", "color": "#4fa8ff"},
    {"grade": 4, "suffix": "IV", "quality": "Épico", "color": "#b388ff"},
    {"grade": 5, "suffix": "V", "quality": "Legendario", "color": "#ffc24a"},
]
PARTS = ["Quitina", "Escama", "Núcleo", "Glándula", "Fibra", "Cristal"]
FORGE = [
    ("alloy", "Aleación Estelar"), ("plasma_fil", "Filamento de Plasma"), ("neutrino", "Placa de Neutrinos"),
    ("quantum", "Circuito Cuántico"), ("lens", "Lente Gravitacional"), ("nebula", "Polvo de Nebulosa"),
]
SLOTS = [
    {"id": "weapon", "name": "Arma", "noun": "Cañón", "stats": {"attack": 0.020, "pve_damage": 0.015}},
    {"id": "armor", "name": "Blindaje", "noun": "Blindaje", "stats": {"defense": 0.020, "hp": 0.015}},
    {"id": "visor", "name": "Visor", "noun": "Visor", "stats": {"hp": 0.015, "capture_resist": 0.04}},
    {"id": "module", "name": "Módulo táctico", "noun": "Módulo", "stats": {"march_speed": 0.020, "load": 0.030}},
    {"id": "reactor", "name": "Reactor", "noun": "Reactor", "stats": {"production": 0.020, "gather_speed": 0.020}},
    {"id": "emblem", "name": "Emblema", "noun": "Emblema", "stats": {"crew_power": 0.030, "research_speed": 0.020}},
]
SETS = ["Vanguardia", "Centinela", "Halcón", "Coloso", "Espectro", "Nébula", "Titán", "Quasar",
        "Púlsar", "Aurora", "Eclipse", "Supernova", "Singular", "Leviatán", "Horizonte"]
SET_BONUS = [
    {"pieces": 3, "effect": "attack", "per_tier": 0.02},
    {"pieces": 6, "effect": "hp", "per_tier": 0.03},
]
TIER_MULT = [1.0, 1.6, 2.4, 3.4, 4.8]
LEVEL_STEP = 0.25          # +25% del valor por nivel de mejora
FORGE_CREDITS = 1500       # × escalón
UPGRADE_CREDITS = 900      # × escalón × nivel actual
REFINE_IN = 4              # 4 de calidad g -> 1 de calidad g+1


def main():
    xeno = json.load(open(os.path.join(ROOT, "data", "catalog_xenoforms.json"), encoding="utf-8"))["species"]
    materials = []
    families = []
    for i, sp in enumerate(xeno):
        part = PARTS[i % len(PARTS)]
        fam = {"id": "x_" + sp["id"], "name": f"{part} de {sp['name']}", "source": "hunt", "species": sp["id"]}
        families.append(fam)
    for fid, fname in FORGE:
        families.append({"id": "f_" + fid, "name": fname, "source": "mining"})
    for fam in families:
        for g in GRADES:
            m = {"id": f"mat_{fam['id']}_{g['grade']}", "family": fam["id"], "name": f"{fam['name']} {g['suffix']}",
                 "grade": g["grade"], "source": fam["source"]}
            if "species" in fam:
                m["species"] = fam["species"]
            materials.append(m)
    hunt_fams = [f for f in families if f["source"] == "hunt"]
    forge_fams = [f for f in families if f["source"] == "mining"]
    equipment = []
    for s_i, set_name in enumerate(SETS):
        tier = s_i // 3 + 1
        for slot_i, slot in enumerate(SLOTS):
            hf1 = hunt_fams[(s_i * 6 + slot_i) % len(hunt_fams)]
            hf2 = hunt_fams[(s_i * 6 + slot_i + 7) % len(hunt_fams)]
            ff = forge_fams[(s_i + slot_i) % len(forge_fams)]
            recipe = {
                f"mat_{hf1['id']}_{tier}": 3 + tier,
                f"mat_{hf2['id']}_{tier}": 2 + tier,
                f"mat_{ff['id']}_{tier}": 2 + tier,
            }
            stats = {k: round(v * TIER_MULT[tier - 1], 4) for k, v in slot["stats"].items()}
            equipment.append({
                "id": f"eq_{s_i + 1:02d}_{slot['id']}", "name": f"{slot['noun']} {set_name}", "slot": slot["id"],
                "set": f"set_{s_i + 1:02d}", "tier": tier, "stats": stats, "recipe": recipe,
                "credits": FORGE_CREDITS * tier,
            })
    sets = [{"id": f"set_{i + 1:02d}", "name": n, "tier": i // 3 + 1} for i, n in enumerate(SETS)]
    out = {
        "version": "mvp-1.0",
        "_doc": "Generado por tools/gen_armory_catalog.py. 150 materiales (30 tipos × 5 calidades) y 90 equipos (15 conjuntos × 6 ranuras) mejorables hasta el nivel 5. tier_by_armory_level[n] = escalón máximo forjable con la Armería en nivel n.",
        "grades": GRADES,
        "slots": [{"id": s["id"], "name": s["name"]} for s in SLOTS],
        "max_level": 5,
        "level_step": LEVEL_STEP,
        "upgrade_credits": UPGRADE_CREDITS,
        "refine_in": REFINE_IN,
        "tier_by_armory_level": [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5],
        "set_bonus": SET_BONUS,
        "drops": {
            "_doc": "Caza: material de la especie con calidad = nivel de la xenoforma (si es abatida: count[nivel-1]; si no, la mitad). Minería: material de forja con calidad = nivel del asteroide.",
            "hunt_count": [2, 3, 3, 4, 5], "mining_count": [1, 2, 2, 3, 3],
        },
        "families": families,
        "materials": materials,
        "sets": sets,
        "equipment": equipment,
    }
    path = os.path.join(ROOT, "data", "catalog_armory.json")
    json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"{len(materials)} materiales, {len(equipment)} equipos -> {path}")
    add_translations(xeno, families, materials, equipment)


PARTS_EN = {"Quitina": "Chitin", "Escama": "Scale", "Núcleo": "Core", "Glándula": "Gland", "Fibra": "Fiber", "Cristal": "Crystal"}
FORGE_EN = {"Aleación Estelar": "Stellar Alloy", "Filamento de Plasma": "Plasma Filament", "Placa de Neutrinos": "Neutrino Plate",
            "Circuito Cuántico": "Quantum Circuit", "Lente Gravitacional": "Gravitational Lens", "Polvo de Nebulosa": "Nebula Dust"}
NOUN_EN = {"Cañón": "Cannon", "Blindaje": "Plating", "Visor": "Visor", "Módulo": "Module", "Reactor": "Reactor", "Emblema": "Emblem"}
SET_EN = {"Vanguardia": "Vanguard", "Centinela": "Sentinel", "Halcón": "Falcon", "Coloso": "Colossus", "Espectro": "Specter",
          "Nébula": "Nebula", "Titán": "Titan", "Quasar": "Quasar", "Púlsar": "Pulsar", "Aurora": "Aurora", "Eclipse": "Eclipse",
          "Supernova": "Supernova", "Singular": "Singular", "Leviatán": "Leviathan", "Horizonte": "Horizon"}
OTHER_EN = {"Arma": "Weapon", "Blindaje": "Plating", "Visor": "Visor", "Módulo táctico": "Tactical module", "Reactor": "Reactor",
            "Emblema": "Emblem", "Común": "Common", "Refinado": "Refined", "Superior": "Superior", "Épico": "Epic", "Legendario": "Legendary"}


def add_translations(xeno, families, materials, equipment):
    """Agrega a data/i18n_en.json los nombres generados (sin pisar los existentes)."""
    path = os.path.join(ROOT, "data", "i18n_en.json")
    tr = json.load(open(path, encoding="utf-8"))
    sp_en = {sp["id"]: tr.get(sp["name"], sp["name"]) for sp in xeno}
    fam_en = {}
    for fam in families:
        if "species" in fam:
            part = fam["name"].split(" de ")[0]
            fam_en[fam["id"]] = f"{sp_en[fam['species']]} {PARTS_EN[part]}"
        else:
            fam_en[fam["id"]] = FORGE_EN[fam["name"]]
        tr.setdefault(fam["name"], fam_en[fam["id"]])
    for m in materials:
        roman = m["name"].rsplit(" ", 1)[1]
        tr.setdefault(m["name"], f"{fam_en[m['family']]} {roman}")
    for e in equipment:
        noun, set_name = e["name"].split(" ", 1)
        tr.setdefault(e["name"], f"{SET_EN[set_name]} {NOUN_EN[noun]}")
    for es, en in list(SET_EN.items()) + list(OTHER_EN.items()):
        tr.setdefault(es, en)
    json.dump(tr, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=0)


if __name__ == "__main__":
    main()
