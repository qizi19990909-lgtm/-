#!/usr/bin/env python3
"""难度模拟：每套装备跑 N 场完整 5 波 + 挑战波（无界面、固定 60 帧、英雄全自动、玩家不操作）。
统计：每波通过率（这一波打完的局数 / N）、每波平均用时、总用时、存活人数、败局停在哪一波。
用法：python3 tools/sim_difficulty.py [N=50] [预设...]   预设见 data/equipment_rules.json 的 sim_presets
结果写到 tools/sim_difficulty_result.txt"""
import subprocess, sys, re, os, statistics, json
from concurrent.futures import ThreadPoolExecutor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = int(sys.argv[1]) if len(sys.argv) > 1 else 50
PRESETS = sys.argv[2:] or ["white", "avg5", "bluepurple5", "purple10"]
NAMES = {"white": "全白 +0", "avg5": "平均 +5（绿蓝混装）", "bluepurple5": "蓝紫 +5", "purple10": "全紫 +10", "starter": "新手流程·不换装（开局 10 件 10 级白 +0）", "starter_autoequip": "新手流程·自动换更好掉落"}
WAVES = [w["name"].split("：")[0] for w in json.load(open(os.path.join(ROOT, "data", "config.json")))["waves"]]
PAT = re.compile(r"SIM preset=(\S+) result=(\S+) time=([\d.]+) alive=(\d+) low=(\d+) wave=(\d+) minhp=([\d.]+) cleared=(\d+) wt=(\S*)")

def run(p):
    out = subprocess.run(["godot", "--headless", "--path", ROOT, "--fixed-fps", "60", "--", "--sim=" + p],
                         capture_output=True, text=True, timeout=600).stdout
    m = PAT.search(out)
    return (m.groups() if m else None), out.count("SCRIPT ERROR")

nw = len(WAVES)
head = "| 装备 | 场数 | " + " | ".join("%s 通过率 / 平均用时" % w for w in WAVES) + " | 全通关率 | 全通关总用时(均值,范围) | 存活(全通关局) | 存活(全部局) | 败局停在 | 脚本错误 |"
lines = [head, "|" + "---|" * (nw + 8)]
for p in PRESETS:
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        res = list(ex.map(run, [p] * N))
    rs = [r for r, _ in res if r]
    errs = sum(e for _, e in res)
    wts = [[float(x) for x in r[8].split(",") if x] for r in rs]
    cells = []
    for i in range(nw):
        c = [w[i] for w in wts if len(w) > i]
        cells.append("%.0f%% / %s" % (100.0 * len(c) / max(1, len(rs)), "%.1fs" % statistics.mean(c) if c else "—"))
    wins = [r for r in rs if r[1] == "win"]
    t = [float(r[2]) for r in wins]
    lose_w = [int(r[5]) for r in rs if r[1] != "win"]
    lines.append("| %s | %d | %s | %.0f%% | %s | %s | %.2f | %s | %d |" % (
        NAMES.get(p, p), len(rs), " | ".join(cells), 100.0 * len(wins) / max(1, len(rs)),
        "%.1fs (%.0f~%.0f)" % (statistics.mean(t), min(t), max(t)) if t else "—",
        "%.2f" % statistics.mean(int(r[3]) for r in wins) if wins else "—",
        statistics.mean(int(r[3]) for r in rs) if rs else 0,
        ("、".join("%s×%d" % (WAVES[w - 1] if w - 1 < nw else w, lose_w.count(w)) for w in sorted(set(lose_w)))) if lose_w else "—", errs))
    print(lines[-1], flush=True)
txt = "\n".join(lines)
print(txt)
open(os.path.join(ROOT, "tools", "sim_difficulty_result.txt"), "w").write(txt + "\n")
