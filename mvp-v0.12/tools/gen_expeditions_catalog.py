#!/usr/bin/env python3
"""Genera data/catalog_expeditions.json: la campaña PvE de Expediciones.

- 6 capítulos × 8 etapas = 48 etapas; la etapa 8 de cada capítulo es un jefe.
- Cada etapa tiene modo Normal y Élite (enemigos más fuertes, premios mejores,
  intentos diarios limitados). El Élite de un capítulo se abre al terminar su
  Normal.
- Se juega con un equipo de hasta 5 tripulantes (su nivel, grado, estrellas y
  rareza definen su fuerza). Las estrellas (1-3) dependen de cuántos caen.
- Primera victoria: Créditos, Insignias, materiales de xenoforma y EXP.
  Repetir (o el barrido con Licencia de Comandante 6): premio reducido.
- Cofres de capítulo al juntar 8, 16 y 24 estrellas.

Uso:  python3 tools/gen_expeditions_catalog.py
Los valores de balance están arriba en constantes para ajustarlos fácilmente.
"""
import json
import os

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

STAGES_PER_CHAPTER = 8
GROWTH = 1.07          # fuerza de los enemigos por etapa
ENEMY_HP = 520.0
ENEMY_ATK = 62.0
BOSS_HP_MULT = 4.0
BOSS_ATK_MULT = 1.8

CHAPTERS = [
    ("Cinturón de Kliptium", "Los primeros nidos xeno acechan entre los asteroides de la frontera.", ["x07", "x11", "x01"], 1),
    ("Nebulosa Carmesí", "Una nebulosa ionizada esconde enjambres que ciegan los sensores.", ["x02", "x12", "x06"], 5),
    ("Fosa de Plasma", "Corrientes de plasma alimentan a los devoradores más voraces.", ["x03", "x05", "x13"], 9),
    ("Velo Umbrío", "Sin luz estelar, los acechadores cazan por el calor de las naves.", ["x04", "x08", "x10"], 13),
    ("Anillos de Quimera", "Restos de una luna rota donde anidan quimeras y colosos.", ["x09", "x14", "x15"], 17),
    ("Corazón de la Colmena", "El origen de la plaga: la Reina Colmena y su guardia.", ["x16", "x18", "x20"], 21),
]
STAGE_NAMES = ["Patrulla", "Emboscada", "Nido menor", "Rastro", "Avanzada", "Cerco", "Guarida", "Jefe"]
ROLES = ["asalto", "vanguardia", "especialista", "asalto", "vanguardia"]


def stage_def(ci, si, species):
    s = ci * STAGES_PER_CHAPTER + si
    g = GROWTH ** s
    boss = si == STAGES_PER_CHAPTER - 1
    count = 3 if ci == 0 else (4 if ci == 1 else 5)
    lvl = min(5, 1 + ci)
    enemies = []
    if boss:
        enemies.append({"species": species[0], "level": min(5, lvl + 1), "role": "vanguardia", "boss": True,
                        "hp": round(ENEMY_HP * g * BOSS_HP_MULT), "atk": round(ENEMY_ATK * g * BOSS_ATK_MULT)})
        count = 2 if ci < 2 else 3
    for i in range(count):
        enemies.append({"species": species[(si + i) % len(species)], "level": lvl, "role": ROLES[i % len(ROLES)],
                        "hp": round(ENEMY_HP * g), "atk": round(ENEMY_ATK * g)})
    mat_q = min(5, 1 + ci // 2 + (1 if boss else 0))
    mat = "mat_x_%s_%d" % (species[si % len(species)], mat_q)
    first = {"credits": round(600 * 1.09 ** s), "insignia": 3 + s // 4, mat: 2 + (2 if boss else 0)}
    if boss:
        first["dark_matter"] = 20 + 10 * ci
    repeat = {"credits": round(220 * 1.09 ** s), "insignia": 1 + s // 12, mat: 1}
    return {
        "id": "%d-%d" % (ci + 1, si + 1), "name": STAGE_NAMES[si], "boss": boss, "enemies": enemies,
        "crew_exp": round(50 * 1.08 ** s), "cmd_exp": round(30 * 1.08 ** s),
        "first": first, "repeat": repeat,
    }


def main():
    chapters = []
    for ci, (name, desc, species, bridge) in enumerate(CHAPTERS):
        stages = [stage_def(ci, si, species) for si in range(STAGES_PER_CHAPTER)]
        chests = [
            {"stars": 8, "reward": {"credits": 3000 * (ci + 1), "insignia": 10 + 5 * ci}},
            {"stars": 16, "reward": {"dark_matter": 40 + 20 * ci, "speedup_1h": 1 + ci // 2}},
            {"stars": 24, "reward": {"recruit_ticket": 1, "insignia": 25 + 10 * ci}},
        ]
        chapters.append({"id": "c%d" % (ci + 1), "name": name, "desc": desc, "requires_bridge": bridge,
                         "stages": stages, "chests": chests})
    out = {
        "version": "mvp-1.0",
        "_doc": "Expediciones: campaña PvE por capítulos con equipos de tripulantes. Generado por tools/gen_expeditions_catalog.py.",
        "fuel": {"name": "Combustible de Expedición", "max": 120, "regen_minutes": 6, "cost_normal": 6, "cost_elite": 12,
                 "refill_amount": 60, "refill_mo": 50, "refills_per_day": 3},
        "team_max": 5,
        "elite": {"daily_attempts": 3, "power_mult": 1.6, "reward_mult": 2, "_doc": "Élite: enemigos ×power_mult, premios ×reward_mult."},
        "sweep_times": [1, 5],
        "unit": {
            "_doc": "Fuerza de un tripulante: base × rareza × (1+per_level·(nivel-1)) × (1+per_grade·(grado-1)) × (1+per_star·(estrellas-1)) × rol.",
            "hp_base": 900, "atk_base": 95, "per_level": 0.08, "per_grade": 0.2, "per_star": 0.12,
            "rarity": {"common": 1.0, "rare": 1.25, "epic": 1.55, "legendary": 1.9},
            "roles": {"vanguardia": {"hp": 1.6, "atk": 0.7}, "asalto": {"hp": 0.8, "atk": 1.45}, "especialista": {"hp": 1.0, "atk": 0.85, "heal": 0.5}},
            "role_by_stat": {"attack": "asalto", "pve_damage": "asalto", "defense": "vanguardia", "hp": "vanguardia",
                             "gather_speed": "especialista", "load": "especialista", "march_speed": "especialista"},
        },
        "battle": {"max_rounds": 15, "crit_chance": 0.15, "crit_mult": 1.5, "spread": 0.1,
                   "stars": {"_doc": "3★ sin bajas, 2★ con max_deaths_2 bajas o menos, 1★ si se gana con más.", "max_deaths_2": 2}},
        "chapters": chapters,
    }
    path = os.path.join(ROOT, "data", "catalog_expeditions.json")
    with open(path, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
        f.write("\n")
    print("ok:", path, sum(len(c["stages"]) for c in chapters), "etapas")


if __name__ == "__main__":
    main()
