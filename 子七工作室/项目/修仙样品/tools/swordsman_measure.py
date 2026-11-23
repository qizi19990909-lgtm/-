"""剑修贴图量头身比：下巴 = 脸部肤色块最下沿 +3px；头顶 = 第一行以黑发为主的行（不含头冠）；脚底 = 不透明像素最下沿。
用法：python3 tools/swordsman_measure.py assets/swordsman_tiers/front_body_0.png ..."""
import numpy as np, sys
from PIL import Image
from scipy import ndimage as ndi
def measure(rgba):
    """rgba: HxWx4 uint8 body layer (no sword). returns top(alpha), hair_top, chin, sole"""
    a = rgba[...,3] > 40
    rgb = rgba[...,:3].astype(float)/255
    mx = rgb.max(2); mn = rgb.min(2); sat = (mx-mn)/(mx+1e-5)
    r,g,b = rgb[...,0],rgb[...,1],rgb[...,2]
    skin = a & (r > g+0.03) & (g > b+0.03) & (sat > 0.10) & (sat < 0.50) & (mx > 0.72)
    ys = np.nonzero(a.any(1))[0]; top, sole = ys.min(), ys.max()
    H = sole-top
    lab, n = ndi.label(skin & (np.arange(a.shape[0])[:,None] < top+0.62*H))
    sz = ndi.sum(skin, lab, index=np.arange(1,n+1))
    face = lab == (np.argmax(sz)+1)
    fy = np.nonzero(face.any(1))[0]
    chin = fy.max() + 3
    lum = rgb.mean(2)
    dark = a & (lum < 0.22) & (sat < 0.35)
    hair_top = top
    for y in range(top, chin):
        row = a[y]; cnt = row.sum()
        if cnt > 20 and dark[y].sum() > 0.6*cnt and dark[y].sum() > 25*a.shape[1]/864:
            hair_top = y; break
    fx = np.nonzero(face.any(0))[0]
    return dict(top=int(top), hair_top=int(hair_top), chin=int(chin), sole=int(sole), face_cx=float((fx.min()+fx.max())/2))
if __name__ == "__main__":
    for f in sys.argv[1:]:
        m = measure(np.array(Image.open(f).convert("RGBA")))
        hd = m["chin"]-m["hair_top"]; hdc = m["chin"]-m["top"]; bd = m["sole"]-m["chin"]
        print(f.split('/')[-1], m, "head(hair):body = 1:%.2f" % (bd/hd), " head(incl crown):body = 1:%.2f" % (bd/hdc))

def face_box(rgba):
    a = rgba[...,3] > 40
    rgb = rgba[...,:3].astype(float)/255
    mx = rgb.max(2); mn = rgb.min(2); sat = (mx-mn)/(mx+1e-5)
    r,g,b = rgb[...,0],rgb[...,1],rgb[...,2]
    skin = a & (r > g+0.03) & (g > b+0.03) & (sat > 0.10) & (sat < 0.50) & (mx > 0.72)
    ys = np.nonzero(a.any(1))[0]; top, sole = ys.min(), ys.max()
    lab, n = ndi.label(skin & (np.arange(a.shape[0])[:,None] < top+0.62*(sole-top)))
    sz = ndi.sum(skin, lab, index=np.arange(1,n+1))
    face = lab == (np.argmax(sz)+1)
    fy = np.nonzero(face.any(1))[0]; fx = np.nonzero(face.any(0))[0]
    return fx.min(), fy.min(), fx.max(), fy.max()

def eye_chin(rgba):
    """返回 (眼睛中心 y, 下巴 y, 两眼中心 x)"""
    x0, y0, x1, y1 = face_box(rgba)
    sub = rgba[y0:y1+1, x0:x1+1].astype(float)
    lum = sub[..., :3].mean(2) / 255
    dark = (lum < 0.32) & (sub[..., 3] > 40)
    lab, n = ndi.label(dark)
    cands = []
    for k in range(1, n + 1):
        ys, xs = np.nonzero(lab == k)
        h = ys.max() - ys.min() + 1; w = xs.max() - xs.min() + 1
        if len(ys) > 30 and h / w > 0.6 and ys.min() > 0 and xs.min() > 0 and xs.max() < x1 - x0:
            cands.append((len(ys), ys.mean() + y0, xs.mean() + x0))
    cands.sort(reverse=True)
    e = cands[:2]
    return float(np.mean([c[1] for c in e])), float(y1 + 3), float(np.mean([c[2] for c in e])), len(cands)
