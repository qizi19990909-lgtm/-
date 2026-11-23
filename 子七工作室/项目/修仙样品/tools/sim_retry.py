#!/usr/bin/env python3
"""重打战役模拟：新手开局（10 件 10 级白装 +0），输了按策略重打（背包/装备保留、满血），每波开始自动换上更好的掉落，最多 30 局。
统计：首杀头目要几局、累计游戏时间；通关挑战波要几局、累计时间；30 局内没打过的比例。
用法：python3 tools/sim_retry.py [N=50] [预设...]（retry_campaign = 从最高波次重打；retry_campaign_w1 = 对照，从第 1 波重打）
结果写到 tools/sim_retry_result.txt"""
import subprocess, sys, re, os, statistics
from concurrent.futures import ThreadPoolExecutor
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
N = int(sys.argv[1]) if len(sys.argv) > 1 else 50
PRESETS = sys.argv[2:] or ["retry_campaign", "retry_campaign_w1"]
NAMES = {"retry_campaign": "输了从已解锁最高波次重打（总经理方案 A）", "retry_campaign_w1": "对照：输了从第 1 波重打"}
PAT = re.compile(r"CAMPAIGN boss_attempt=(-?\d+) boss_time=(-?[\d.]+) ch_attempt=(-?\d+) ch_time=(-?[\d.]+) attempts=(\d+) total=([\d.]+) max_wave=(\d+)")
CAP = 30

EXTRA = [a for a in os.environ.get("SIM_EXTRA", "").split() if a]   # 例：SIM_EXTRA="--sim-drop-boost=3"（仅模拟，不改配置）
OUTFILE = os.environ.get("SIM_OUT", "sim_retry_result.txt")

def run(p):
    out = subprocess.run(["godot", "--headless", "--path", ROOT, "--fixed-fps", "60", "--", "--sim=" + p] + EXTRA, capture_output=True, text=True, timeout=1800).stdout
    m = PAT.search(out)
    return (m.groups() if m else None), out.count("SCRIPT ERROR")

def stat(vals):
    return ("%.1f / %.1f" % (statistics.mean(vals), statistics.median(vals))) if vals else "—"

lines = (["模拟参数：" + " ".join(EXTRA), ""] if EXTRA else []) + ["上限 %d 局；时间为游戏内时间（含波间等待，不含菜单操作），单位分钟。局数 = 第几局首次做到（第 1 局 = 开局那一局）。" % CAP, "",
         "| 策略 | 场数 | 首杀头目：局数 均值/中位 | 首杀头目：累计分钟 均值/中位 | %d 局内没杀掉头目 | 通关挑战波：局数 均值/中位 | 通关挑战波：累计分钟 均值/中位 | %d 局内没通关挑战波 | 没杀掉头目的局最高打到 | 脚本错误 |" % (CAP, CAP),
         "|---|---|---|---|---|---|---|---|---|---|"]
for p in PRESETS:
    with ThreadPoolExecutor(max_workers=os.cpu_count() or 4) as ex:
        res = list(ex.map(run, [p] * N))
    rs = [r for r, _ in res if r]
    errs = sum(e for _, e in res) + (N - len(rs))
    b = [r for r in rs if int(r[0]) > 0]
    c = [r for r in rs if int(r[2]) > 0]
    mw = [int(r[6]) for r in rs if int(r[0]) <= 0]
    lines.append("| %s | %d | %s | %s | %d/%d（%.0f%%） | %s | %s | %d/%d（%.0f%%） | %s | %d |" % (
        NAMES.get(p, p), len(rs), stat([int(r[0]) for r in b]), stat([float(r[1]) / 60 for r in b]),
        len(rs) - len(b), len(rs), 100.0 * (len(rs) - len(b)) / max(1, len(rs)),
        stat([int(r[2]) for r in c]), stat([float(r[3]) / 60 for r in c]),
        len(rs) - len(c), len(rs), 100.0 * (len(rs) - len(c)) / max(1, len(rs)),
        ("第%d波" % max(mw) if mw else "—") + ("（多数第%d波）" % statistics.mode(mw) if mw else ""), errs))
    print(lines[-1], flush=True)
txt = "\n".join(lines)
print(txt)
open(os.path.join(ROOT, "tools", OUTFILE), "w").write(txt + "\n")
