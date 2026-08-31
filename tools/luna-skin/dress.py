"""자세 묶음을 격자로 만들고, 생성 결과를 기본 아틀라스 자리에 맞춰 되돌린다."""
import os, sys
from PIL import Image
import numpy as np

ASSETS = os.path.expanduser('~/Documents/git-rehyundesign/apps/retto-pet/assets')
CW, CH = 224, 240
SLOT_W, SLOT_H, CAT_H, FOOT_PAD = 448, 480, 380, 50

def base():
    return Image.open(os.path.join(ASSETS, 'spritesheet.webp')).convert('RGBA')

def cellsOf(spec):
    """spec = [(row, count), ...] -> [(r,c,cell)]"""
    s = base(); out = []
    for r, n in spec:
        for c in range(n):
            out.append((r, c, s.crop((c*CW, r*CH, (c+1)*CW, (r+1)*CH))))
    return out

def make_grid(items, cols, path, bg=(3,105,243,255)):
    rows = (len(items)+cols-1)//cols
    g = Image.new('RGBA', (SLOT_W*cols, SLOT_H*rows), bg)
    for i, (_, _, cell) in enumerate(items):
        bb = cell.split()[3].getbbox(); cat = cell.crop(bb)
        w = round(cat.width*CAT_H/cat.height)
        cat = cat.resize((w, CAT_H), Image.LANCZOS)
        ox, oy = (i%cols)*SLOT_W, (i//cols)*SLOT_H
        g.alpha_composite(cat, (ox+(SLOT_W-w)//2, oy+SLOT_H-FOOT_PAD-CAT_H))
    g.convert('RGB').save(path)
    return g.size, rows

def feet(img, frac=0.08):
    a = np.array(img.split()[3]) > 8
    ys, xs = np.nonzero(a); bot = ys.max(); h = bot-ys.min()+1
    band = a[bot-max(4, round(h*frac))+1:bot+1, :]
    x = np.nonzero(band.any(axis=0))[0]
    return float(x.max()-x.min()+1), (float(x.min())+x.max()+1)/2, int(bot)

def place_back(items, gen_dir, cols, out_sheet):
    """생성한 칸을 원래 칸의 발 폭·발 중앙·바닥선에 맞춰 되돌린다."""
    for i, (r, c, cell) in enumerate(items):
        gi = Image.open(os.path.join(gen_dir, f'k-{i}.png')).convert('RGBA')
        gw, gcx, gbot = feet(gi)
        bw, bcx, bbot = feet(cell)
        s = bw/gw
        bb = gi.split()[3].getbbox(); crop = gi.crop(bb)
        nw, nh = round(crop.width*s), round(crop.height*s)
        big = crop.resize((nw, nh), Image.LANCZOS)
        new = Image.new('RGBA', (CW, CH), (0,0,0,0))
        ox = round(bcx - (gcx-bb[0])*s); oy = round(bbot - (gbot-bb[1])*s)
        new.alpha_composite(big, (max(0,ox), max(0,oy)), (max(0,-ox), max(0,-oy), nw, nh))
        out_sheet.paste(new, (c*CW, r*CH))
    return out_sheet
