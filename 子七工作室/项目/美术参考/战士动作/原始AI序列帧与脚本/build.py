import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageEnhance, ImageChops
import os
OUT='/workspace/子七工作室/项目/美术参考/战士动作'
W,H=1280,720
from scipy import ndimage
def cells(path):
    im=Image.open(path).convert('RGB')
    A_=np.asarray(im).astype(int); M=A_.min(axis=2)<228
    res=[]
    for r in range(2):
        for c in range(3):
            xa,xb=c*W//3,(c+1)*W//3
            rs=M[:,xa:xb].sum(1)
            lo=240; seg=rs[lo:430]
            # choose split: center of longest run of minimal rows
            mn=seg.min(); idx=np.where(seg<=mn+1)[0]
            split=lo+int(np.median(idx))
            ya,yb=(0,split) if r==0 else (split,H)
            cell=im.crop((xa,ya,xb,yb)); a=A_[ya:yb,xa:xb]
            mask=M[ya:yb,xa:xb].copy()
            lab,n=ndimage.label(ndimage.binary_dilation(mask,iterations=2))
            keep=np.zeros_like(mask)
            for k in range(1,n+1):
                comp=lab==k; area=(comp&mask).sum()
                if area<25: continue
                ys,xs=np.where(comp)
                touch=(r==0 and ys.max()>=comp.shape[0]-3) or (r==1 and ys.min()<=2) or xs.min()<=1 or xs.max()>=comp.shape[1]-2
                if touch and area<4000: continue
                keep|=comp&mask
            a2=a.copy(); a2[~ndimage.binary_dilation(keep,iterations=2)]=255
            cell=Image.fromarray(a2.astype('uint8'))
            mask=keep
            rows=np.where(mask.sum(1)>2)[0]; cols=np.where(mask.sum(0)>2)[0]
            y0,y1,x0,x1=rows[0],rows[-1],cols[0],cols[-1]
            dark=(a.max(axis=2)<80)&mask
            bh=y1-y0
            band=dark[int(y1-0.2*bh):y1+1]
            xs=np.where(band.sum(0)>0)[0]
            fx=int(xs.mean()) if len(xs) else (x0+x1)//2
            res.append(dict(img=cell,bbox=(x0,y0,x1,y1),feet=fx,h=bh))
    return res
SH={k:cells(k+'.jpg') for k in ['attack','run','death','fear','revive','idle_stun','hit_freeze']}
# scale reference: standing frame heights
ref={'attack':0,'run':0,'death':1,'fear':5,'revive':4,'idle_stun':0,'hit_freeze':0}
TARGET=230
CW,CH=400,360; BASE=340; AX=190
def place(sheet,idx,mode='feet',dx=0,dy=0):
    s=SH[sheet]; f=s[idx]; sc=TARGET/s[ref[sheet]]['h']
    cell=f['img']; x0,y0,x1,y1=f['bbox']
    crop=cell.crop((x0,y0,x1+1,y1+1))
    crop=crop.resize((max(1,int(crop.width*sc)),max(1,int(crop.height*sc))),Image.LANCZOS)
    canvas=Image.new('RGB',(CW,CH),'white')
    if mode=='feet': ax=f['feet']
    else: ax=cell.width//2
    px=int(AX-(ax-x0)*sc)+dx; py=BASE-crop.height+dy
    # paste with white as transparent via darker blend
    region=canvas.crop((px,py,px+crop.width,py+crop.height))
    canvas.paste(ImageChops.darker(region,crop),(px,py))
    return canvas
def squash(img,sy=0.975):
    w,h=img.size; ch=int(h*sy)
    out=Image.new('RGB',(w,h),'white'); out.paste(img.resize((w,ch),Image.LANCZOS),(0,h-ch)); return out
def rot(img,deg):
    return img.rotate(deg,resample=Image.BICUBIC,center=(AX,BASE),fillcolor='white')
def shift(img,dx,dy=0):
    out=Image.new('RGB',img.size,'white'); out.paste(img,(dx,dy)); return out
def flash(img):
    a=np.asarray(img).astype(float); w=(a.min(2)>=232)
    b=a*0.35+255*0.65; b[w]=255; return Image.fromarray(b.astype('uint8'))
def tint_ice(img,k=0.25):
    a=np.asarray(img).astype(float); w=(a.min(2)>=232)
    b=a*(1-k)+np.array([170,215,255])*k; b[w]=255; return Image.fromarray(b.astype('uint8'))
# actions: name, list of (frame, duration_ms, real_flag)
A=[]
def R(sh,i,**k): return place(sh,i,**k)
at=[R('attack',i) for i in range(6)]
A.append(('攻击','attack',[(at[0],150,1),(at[1],110,1),(at[2],260,1),(at[3],70,1),(at[4],220,1),(at[0],200,1)]))
rn=[R('run',i) for i in range(6)]
A.append(('移动','run',[(f,100,1) for f in rn]))
idl=[R('idle_stun',i) for i in range(3)]
A.append(('待机','idle',[(idl[0],220,1),(squash(idl[0]),220,0),(idl[1],260,1),(idl[2],220,1),(squash(idl[2],0.985),220,0)]))
hf=[R('hit_freeze',i) for i in range(6)]
A.append(('受击','hit',[(hf[0],150,1),(flash(hf[1]),70,0),(hf[1],140,1),(shift(hf[2],-10),160,1),(shift(hf[2],-5),110,0),(hf[0],200,1)]))
st=[R('idle_stun',i) for i in range(3,6)]
A.append(('眩晕','stun',[(rot(st[0],3),140,1),(st[1],140,1),(rot(st[2],-3),140,1),(st[1],140,0)]))
fz=[R('hit_freeze',i) for i in range(3,6)]
fzl=tint_ice(fz[2],0.12)
A.append(('冰冻','freeze',[(fz[0],180,1),(fz[1],180,1),(fz[2],200,1),(shift(fzl,2),60,0),(shift(fzl,-2),60,0),(shift(fzl,2),60,0),(fz[2],400,0),(shift(fzl,-2),60,0),(shift(fzl,2),60,0)]))
fr=[R('fear',i) for i in range(6)]
A.append(('恐惧','fear',[(fr[0],160,1),(fr[1],160,1),(shift(fr[1],3),80,0),(fr[2],130,1),(fr[3],130,1),(fr[4],130,1),(fr[5],120,1),(shift(fr[5],-3),80,0),(shift(fr[5],3),80,0)]))
dt=[R('death',i,mode='cell') for i in range(6)]
A.append(('死亡','death',[(dt[0],150,1),(dt[1],150,1),(dt[2],170,1),(dt[3],150,1),(dt[4],200,1),(dt[5],900,1)]))
rv=[R('revive',i,mode='cell') for i in [0,2,1,3,4]]
A.append(('复活','revive',[(rv[0],350,1),(rv[1],200,1),(rv[2],200,1),(rv[3],220,1),(rv[4],600,1)]))
os.makedirs(OUT,exist_ok=True)
fontb=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',30,index=2)
fonts=ImageFont.truetype('/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc',16,index=2)
def save_gif(path,frames,durs):
    pal=[f.convert('P',palette=Image.ADAPTIVE,colors=128) for f in frames]
    frames[0].save(path,save_all=True,append_images=frames[1:],duration=durs,loop=0,optimize=True,disposal=1)
order=['待机','移动','攻击','受击','眩晕','冰冻','恐惧','死亡','复活']
A.sort(key=lambda t:order.index(t[0]))
allf=[];alld=[]
for i,(cn,en,fl) in enumerate(A):
    fr_=[f for f,_,_ in fl]; ds=[d for _,d,_ in fl]
    save_gif(f'{OUT}/战士_{i+1:02d}_{cn}.gif',fr_,ds)
    for rep in range(2):
        for f,d,_ in fl:
            c=Image.new('RGB',(CW,CH+50),'white'); c.paste(f,(0,50))
            dr=ImageDraw.Draw(c); t=f'{cn}'
            dr.text((CW//2,26),t,font=fontb,fill=(40,40,40),anchor='mm')
            dr.text((CW-10,26),f'{i+1}/9',font=fonts,fill=(150,150,150),anchor='rm')
            allf.append(c); alld.append(d)
save_gif(f'{OUT}/战士_全动作合集.gif',allf,alld)
# overview
TW,TH=200,180; maxn=max(len(fl) for _,_,fl in A); LW=110
ov=Image.new('RGB',(LW+maxn*TW,len(A)*(TH+24)+60),'white'); dr=ImageDraw.Draw(ov)
dr.text((10,30),'男战士 动作帧总览（橙色“程序补强”=程序变换帧，其余黑字为AI真实姿势帧）',font=fonts,fill=(0,0,0),anchor='lm')
for r,(cn,en,fl) in enumerate(A):
    y=60+r*(TH+24)
    dr.text((LW//2,y+TH//2),cn,font=fontb,fill=(40,40,40),anchor='mm')
    for c,(f,d,real) in enumerate(fl):
        x=LW+c*TW
        ov.paste(f.resize((TW,TH),Image.LANCZOS),(x,y))
        dr.rectangle((x,y,x+TW-1,y+TH-1),outline=(220,220,220))
        lab=f'#{c+1} {d}ms'+('' if real else ' 程序补强')
        dr.text((x+4,y+TH+2),lab,font=fonts,fill=(0,0,0) if real else (200,80,0))
ov.save(f'{OUT}/战士_动作帧总览.png',optimize=True)
for cn,en,fl in A: print(cn,len(fl),'real',sum(r for _,_,r in fl))
