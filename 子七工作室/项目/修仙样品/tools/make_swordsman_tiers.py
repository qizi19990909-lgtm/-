"""剑修七品阶外观 v2.1（真 1:1 头身，正面 + 3/4 侧面）：把 AI 生成的原图去白底、拆出剑层、
把头缩放到「头顶(黑发，不含头冠)→下巴 = 下巴→脚底」、各档身体（下巴→脚底）统一高度，再对齐脚底锚点。

输入：assets/swordsman_tiers/raw/front_<i>.jpg、side_<i>.jpg（.gdignore，不导入游戏）、raw/grips.json（握剑点，原图坐标，目测标定）
输出：assets/swordsman_tiers/<view>_body_<i>.png、<view>_sword_<i>.png、meta.json
用法：python3 tools/make_swordsman_tiers.py [--debug]
"""
import json, os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from swordsman_measure import measure, eye_chin

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "assets/swordsman_tiers/raw")
OUT = os.path.join(ROOT, "assets/swordsman_tiers")
VIEWS = ["front", "side"]
OUT_H = 380
PAD = 24
DEBUG = "--debug" in sys.argv


def fg_mask(rgb):
    mn = rgb.min(axis=2).astype(int); mx = rgb.max(axis=2).astype(int)
    whiteish = (mn > 228) & (mx - mn < 22)
    lab, n = ndi.label(whiteish)
    border = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    bg = np.isin(lab, list(border))
    sizes = ndi.sum(np.ones_like(lab), lab, index=np.arange(1, n + 1))
    means = ndi.mean(mn, lab, index=np.arange(1, n + 1))
    cys = ndi.center_of_mass(np.ones_like(lab), lab, index=np.arange(1, n + 1))
    rows = np.nonzero((~bg).any(axis=1))[0]
    head_zone = rows.min() + 0.55 * (rows.max() - rows.min())
    for i in range(n):
        # 封闭的大块纯白（手臂和身体之间的空隙）算背景；头部区域的白（眼白、高光）保留
        if (i + 1) not in border and sizes[i] > 600 and means[i] > 247 and cys[i][0] > head_zone:
            bg |= lab == (i + 1)
    fg = ndi.binary_opening(~bg, iterations=1)
    lab2, n2 = ndi.label(fg)
    if n2 > 1:
        s = ndi.sum(fg, lab2, index=np.arange(1, n2 + 1))
        fg = np.isin(lab2, [i + 1 for i in range(n2) if s[i] > 300])
    return fg


def soft_alpha(rgb, fg):
    a = fg.astype(float)
    edge = fg & ~ndi.binary_erosion(fg, iterations=2)
    mn = rgb.min(axis=2).astype(float)
    k = np.clip((255.0 - mn) / 70.0, 0.0, 1.0)
    a[edge] = np.minimum(a[edge], k[edge] + 0.15)
    a = np.clip(ndi.gaussian_filter(a, 0.6) * fg, 0, 1)
    out = rgb.astype(float)
    m = (a > 0.05) & (a < 0.98)
    for ch in range(3):
        c = out[..., ch]
        c[m] = np.clip((c[m] - (1 - a[m]) * 255.0) / a[m], 0, 255)
    return out.astype(np.uint8), (a * 255).astype(np.uint8)


def sword_mask(fg, grip, view):
    h, w = fg.shape
    g = np.array(grip, float)
    # 剑尖：正面图剑在左下（最左的前景点），侧面图剑在右边（最右的前景点）
    ys, xs = np.nonzero(fg[int(g[1]) - 120:int(g[1]) + 320])
    ys = ys + int(g[1]) - 120
    i = np.argmin(xs) if view == "front" else np.argmax(xs)
    tip = np.array([xs[i], ys[i]], float)
    axis = g - tip; L = np.linalg.norm(axis); u = axis / L; nrm = np.array([-u[1], u[0]])
    yy, xx = np.mgrid[0:h, 0:w]
    px = xx - tip[0]; py = yy - tip[1]
    t = px * u[0] + py * u[1]; d = np.abs(px * nrm[0] + py * nrm[1])
    width = np.where(t < L - 80, 22, 46)
    m = fg & (t > -8) & (t < L + 36) & (d < width)
    lab, n = ndi.label(m)
    if n > 1:
        s = ndi.sum(m, lab, index=np.arange(1, n + 1))
        m = lab == (np.argmax(s) + 1)
    grow = ndi.binary_dilation(m, iterations=3) & fg & (t > -12) & (t < L - 60) & (d < 28)
    return m | grow, tip


def main():
    grips = json.load(open(os.path.join(RAW, "grips.json")))
    items = []
    for view in VIEWS:
        for i in range(7):
            rgb = np.array(Image.open(os.path.join(RAW, f"{view}_{i}.jpg")).convert("RGB"))
            fg = fg_mask(rgb)
            col, a = soft_alpha(rgb, fg)
            sm, tip = sword_mask(fg, grips[view][i], view)
            rest = (a > 0) & ~sm
            lab, n = ndi.label(rest)
            if n > 1:
                sz = ndi.sum(rest, lab, index=np.arange(1, n + 1))
                rest = np.isin(lab, [k + 1 for k in range(n) if sz[k] > 800])
            body_rgba = np.dstack([col, np.where(rest, a, 0).astype(np.uint8)])
            sword_rgba = np.dstack([col, np.where(sm, a, 0).astype(np.uint8)])
            m = measure(body_rgba)
            e = eye_chin(body_rgba)
            items.append(dict(view=view, i=i, body=body_rgba, sword=sword_rgba, m=m, e2c=e[1] - e[0],
                              grip=grips[view][i], tip=tip.tolist()))
    # 头高：头冠把发髻整个挡住的档（检测到的黑发顶比不透明顶低很多）用「眼睛到下巴 × 同角度其他档的平均倍数」估算
    for view in VIEWS:
        vs = [it for it in items if it["view"] == view]
        ok = [it for it in vs if it["m"]["hair_top"] - it["m"]["top"] < 40]
        k = float(np.median([(it["m"]["chin"] - it["m"]["hair_top"]) / it["e2c"] for it in ok]))
        for it in vs:
            m = it["m"]
            it["head"] = (m["chin"] - m["hair_top"]) if it in ok else k * it["e2c"]
            it["bodyh"] = m["sole"] - m["chin"]
    B0 = float(np.median([it["bodyh"] for it in items]))     # 统一的身体高度（下巴→脚底，原图像素）
    for it in items:
        sb = B0 / it["bodyh"]; sh = B0 / (it["head"] * sb)   # 身体缩放；头在身体缩放之外再缩放，最终头高 = 身体高 = B0
        m = it["m"]; Hh, Ww = it["body"].shape[:2]
        foot_x = float(np.mean(np.nonzero(it["body"][m["sole"] - 40:m["sole"] + 1, :, 3].max(axis=0) > 40)[0]))
        BIG = 2400; ox, oy = (BIG - Ww) // 2, BIG - Hh - 200    # 大画布，原图贴在下方，留出头放大的空间
        def scaled(arr, s, px, py, tx, ty):
            # 以 (px,py) 为支点缩放 s 倍，再把支点放到大画布的 (tx,ty)
            im = Image.fromarray(arr, "RGBA")
            im = im.resize((max(1, int(round(Ww * s))), max(1, int(round(Hh * s)))), Image.LANCZOS)
            canvas = Image.new("RGBA", (BIG, BIG), (0, 0, 0, 0))
            canvas.alpha_composite(im, (int(round(tx - px * s)), int(round(ty - py * s))))
            return canvas
        sole_t = (ox + foot_x, oy + m["sole"])
        lower = it["body"].copy(); lower[:m["chin"] - 2, :, 3] = 0
        upper = it["body"].copy(); upper[m["chin"] - 2:, :, 3] = 0
        body_l = scaled(lower, sb, foot_x, m["sole"], *sole_t)
        chin_t = (sole_t[0] + (m["face_cx"] - foot_x) * sb, sole_t[1] - (m["sole"] - m["chin"]) * sb)
        head_l = scaled(upper, sb * sh, m["face_cx"], m["chin"], *chin_t)
        body_l.alpha_composite(head_l)
        sword_l = scaled(it["sword"], sb, foot_x, m["sole"], *sole_t)
        tr = lambda p: [sole_t[0] + (p[0] - foot_x) * sb, sole_t[1] + (p[1] - m["sole"]) * sb]
        it.update(body_big=np.array(body_l), sword_big=np.array(sword_l), grip=tr(it["grip"]), tip=tr(it["tip"]),
                  foot=int(round(sole_t[1])), cx=sole_t[0])
        print(it["view"], it["i"], "head %.0f body %.0f -> 身体缩放 %.3f 头额外缩放 %.3f" % (it["head"], it["bodyh"], sb, sh))
    # 对齐：脚底和脚的中线
    tops = []
    halfw = 0
    for it in items:
        al = np.maximum(it["body_big"][..., 3], it["sword_big"][..., 3])
        ys = np.nonzero(al.max(axis=1) > 0)[0]; xs = np.nonzero(al.max(axis=0) > 0)[0]
        tops.append(it["foot"] - ys.min())
        halfw = max(halfw, it["cx"] - xs.min(), xs.max() - it["cx"])
    above = max(tops) + 14; below = 10; halfw = int(halfw) + 10
    scale = OUT_H / (above + below)
    W = int(round(2 * halfw * scale)); H = OUT_H
    meta = {"size": [W, H], "foot": [round(W / 2.0, 1), round(above * scale, 1)], "body_h": round(B0 * scale, 1), "front": [], "side": []}
    for it in items:
        box = (int(round(it["cx"] - halfw)), int(it["foot"] - above), int(round(it["cx"] + halfw)), int(it["foot"] + below))
        place = lambda arr: Image.fromarray(arr, "RGBA").crop(box).resize((W, H), Image.LANCZOS)
        v, i = it["view"], it["i"]
        place(it["body_big"]).save(os.path.join(OUT, f"{v}_body_{i}.png"), optimize=True)
        sw = place(it["sword_big"])
        bx = sw.getbbox()
        crop = Image.new("RGBA", (bx[2] - bx[0] + 2 * PAD, bx[3] - bx[1] + 2 * PAD), (0, 0, 0, 0))
        crop.paste(sw.crop(bx), (PAD, PAD))
        crop.save(os.path.join(OUT, f"{v}_sword_{i}.png"), optimize=True)
        tr = lambda p: [round((p[0] - box[0]) * scale, 1), round((p[1] - box[1]) * scale, 1)]
        meta[v].append({"grip": tr(it["grip"]), "tip": tr(it["tip"]), "sword_origin": [bx[0] - PAD, bx[1] - PAD]})
    json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"), ensure_ascii=False, indent=1)
    print("canvas", W, H, "scale", round(scale, 4))


if __name__ == "__main__":
    main()
