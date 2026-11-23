"""从角色图里抠出武器像素，生成单独的「武器层」图片（带透明留边）。
游戏里武器层叠在角色身上，按武器品质重新上色并发光。
只处理工作室自有占位图；输出到 assets/warrior/weapon/ 和 assets/heroes/*_weapon.png。
用法：在工程根目录 python3 tools/extract_weapon_layers.py
"""
import glob, os
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

PAD = 24  # 留边（像素），给发光描边留空间


def hsv(a):
    r, g, b = [a[..., i] / 255.0 for i in range(3)]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    s = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    d = np.maximum(mx - mn, 1e-6)
    h = np.where(mx == r, ((g - b) / d) % 6, np.where(mx == g, (b - r) / d + 2, (r - g) / d + 4)) * 60
    return h, s, mx


def poly_mask(shape, pts):
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).polygon(pts, fill=1)
    return np.array(im).astype(bool)


def band_mask(shape, p0, p1, half):
    im = Image.new("L", (shape[1], shape[0]), 0)
    ImageDraw.Draw(im).line([p0, p1], fill=1, width=half * 2)
    return np.array(im).astype(bool)


def blade_auto(a):
    _, s, v = hsv(a)
    m = (a[..., 3] > 100) & (s < 0.22) & (v > 0.3)
    lab, n = ndimage.label(m, structure=np.ones((3, 3)))
    best, bs = None, 0
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        if len(ys) < 120 or len(ys) > 4000:
            continue
        ev = np.linalg.eigvalsh(np.cov(np.vstack([xs, ys])))
        ratio = np.sqrt(ev[1] / max(ev[0], 1e-3))
        if ratio < 2.5 or np.sqrt(ev[1]) < 12:
            continue
        if len(ys) * ratio > bs:
            bs, best = len(ys) * ratio, i
    return lab == best if best else np.zeros(m.shape, bool)


# 自动识别失败的几帧：手工给出刀身所在区域（原图像素坐标）
BLADE_REGION = {
    "attack_4": ("band", (165, 186), (252, 249), 11),
    "death_0": ("box", (85, 190, 178, 245)),
    "death_2": ("box", (50, 190, 120, 268)),
}


def blade_mask(name, a):
    if name in BLADE_REGION:
        r = BLADE_REGION[name]
        if r[0] == "band":
            reg = band_mask(a.shape, r[1], r[2], r[3])
        else:
            x0, y0, x1, y1 = r[1]
            reg = np.zeros(a.shape[:2], bool); reg[y0:y1, x0:x1] = True
        _, s, v = hsv(a)
        m = reg & (a[..., 3] > 100) & (s < 0.25) & (v > 0.3)
        lab, n = ndimage.label(m, structure=np.ones((3, 3)))
        if n == 0:
            return m
        sizes = ndimage.sum(m, lab, range(1, n + 1))
        return lab == (np.argmax(sizes) + 1)
    return blade_auto(a)


def save_layer(a, mask, out):
    mask = ndimage.binary_dilation(mask, iterations=1) & (a[..., 3] > 0)
    w = a.copy()
    w[~mask, 3] = 0
    h, wd = a.shape[:2]
    big = np.zeros((h + PAD * 2, wd + PAD * 2, 4), np.uint8)
    big[PAD:PAD + h, PAD:PAD + wd] = w.astype(np.uint8)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    Image.fromarray(big).save(out, optimize=True)
    return int(mask.sum())


def main():
    for p in sorted(glob.glob("assets/warrior/*_[0-9].png")):
        name = os.path.splitext(os.path.basename(p))[0]
        a = np.array(Image.open(p).convert("RGBA")).astype(float)
        n = save_layer(a, blade_mask(name, a), "assets/warrior/weapon/%s.png" % name)
        print(name, n)
    # 弓手：弓（深棕色 + 弓弦）
    a = np.array(Image.open("assets/heroes/archer.png").convert("RGBA")).astype(float)
    h, s, v = hsv(a)
    reg = poly_mask(a.shape, [(172, 146), (198, 146), (198, 178), (170, 232), (150, 250), (118, 270), (84, 286), (70, 278), (76, 262), (112, 248), (140, 232), (158, 210), (174, 172)])
    string = poly_mask(a.shape, [(176, 150), (190, 152), (100, 272), (88, 270)])
    brown = (h > 5) & (h < 45) & (s > 0.3) & (v > 0.12) & (v < 0.62)
    light = (s < 0.18) & (v > 0.7)
    m = (a[..., 3] > 100) & ((reg & brown) | (string & light))
    print("archer", save_layer(a, m, "assets/heroes/archer_weapon.png"))
    # 法师：法杖（棕色杖身 + 紫色法球）
    a = np.array(Image.open("assets/heroes/mage.png").convert("RGBA")).astype(float)
    h, s, v = hsv(a)
    reg = poly_mask(a.shape, [(140, 132), (176, 128), (176, 150), (160, 162), (152, 232), (134, 323), (106, 323), (124, 232), (134, 162)])
    yy, xx = np.mgrid[0:a.shape[0], 0:a.shape[1]]
    orb = (xx - 157) ** 2 + (yy - 125) ** 2 < 15 ** 2
    brown = (h > 5) & (h < 45) & (s > 0.3) & (v > 0.12) & (v < 0.7)
    m = (a[..., 3] > 100) & ((reg & brown) | orb)
    print("mage", save_layer(a, m, "assets/heroes/mage_weapon.png"))


if __name__ == "__main__":
    main()
