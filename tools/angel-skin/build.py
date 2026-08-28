#!/usr/bin/env python3
"""천사 날개 스킨 아틀라스(spritesheet-angel.webp)를 기본 아틀라스에서 만든다.

기본 아틀라스의 80칸에 날개를 얹는다. 몸은 원본 크기 그대로 두고 날개만 붙인다 —
날개를 키우면 칸 밖으로 나가므로 크기와 어깨 위치가 서로 묶여 있다.

    python3 tools/angel-skin/build.py            # assets/spritesheet-angel.webp 갱신
    python3 tools/angel-skin/build.py --check    # 다시 만들어도 같은지만 본다

Pillow 가 필요하다. 결과 PNG 는 cwebp 로 무손실 인코딩해 넣는다:

    cwebp -lossless -exact -z 9 out.png -o assets/spritesheet-angel.webp
"""
import argparse, math, os, subprocess, sys, tempfile
from PIL import Image

ROOT   = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
ASSETS = os.path.join(ROOT, 'assets')
WINGS  = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'wings')

CW, CH, COLS, ROWS = 224, 240, 8, 12
FEET_Y = 235            # 발이 닿는 줄. 기본 아틀라스의 앉은 자세와 같은 값

# ── 날개 배치 값 ─────────────────────────────────────────────────
# 몸을 줄이지 않고 날개가 칸 안에 들어오게 잡은 조합이다. 하나만 키우면 칸을 넘는다.
BODY   = 1.00           # 몸 배율. 1.0 = 기본 아틀라스와 같은 크기
WH_R   = 0.53           # 앞모습 날개 높이 / 몸 높이
AY_R   = 0.57           # 어깨 y (몸 위에서부터의 비율)
# 목털이 화면 왼쪽에서 더 넓어 같은 자리에 달면 왼쪽 날개만 묻힌다. 왼쪽을 더 바깥에 단다.
LX_R   = 0.35           # 왼쪽 어깨 x (몸 왼쪽에서부터의 비율)
RX_R   = 0.52           # 오른쪽 어깨 x
BASE   = 16             # 날개를 벌리는 기본 각도(도)
AMP    = 8              # 살랑임 진폭(도). 프레임마다 사인 곡선으로 흔든다

# 행 -> 칸별 날개 종류.  F 앞모습 · S 옆(오른쪽 보고 달림) · L 옆(왼쪽) · D 접힘
PLAN = {0:'FFFFFFF', 1:'SSSSSSSS', 2:'LLLLLLLL', 3:'FFFF', 4:'SSFFF', 5:'FFFDFDFD',
        6:'FFFFFF', 7:'FFFFFF', 8:'FFFFFF', 9:'FFFFFFFF', 10:'FFFFFFFF', 11:'DDDDDD'}
# 엎드리거나 자는 칸의 날개. 접지 않고 편 채로 두고 몸 뒤로 그려 좌우로 살짝 나오게 한다 —
# 접어서 등에 얹으면 웅크린 실루엣을 덮어 자세가 안 읽혔다.
# 값은 (날개높이비, 왼쪽어깨 x, 오른쪽어깨 x, 어깨 y). 자세마다 머리 방향이 달라 행별로 준다.
#   행 5 엎드림 — 머리가 왼쪽, 등·엉덩이가 오른쪽
#   행 11 자는 중 — 몸 덩어리가 왼쪽, 머리가 오른쪽
LIE = {5: (0.78, 0.34, 0.60, 0.48), 11: (0.78, 0.26, 0.50, 0.48)}

def _load(name):
    return Image.open(os.path.join(WINGS, name)).convert('RGBA')

FRONT  = {'L': _load('front-left.png'), 'R': _load('front-right.png')}
SIDE   = _load('side.png')

def _shrink(cell):
    """몸을 BODY 배율로 다시 앉힌다. 발은 언제나 FEET_Y 에 닿는다."""
    bb = cell.split()[3].getbbox()
    crop = cell.crop(bb)
    nw, nh = round(crop.width*BODY), round(crop.height*BODY)
    body = Image.new('RGBA', (CW, CH), (0,0,0,0))
    body.alpha_composite(crop.resize((nw, nh), Image.LANCZOS), (round(CW/2-0.5-nw/2), FEET_Y-nh))
    return body

def _place(body, wing, w_h, ax_r, ay_r, tx_r, ty_r, angle, flip=False):
    """wing 을 몸 bbox 기준 비율 자리에 얹은 레이어를 낸다.
    ax_r·ay_r 은 날개에서 축이 될 지점(0~1), tx_r·ty_r 은 몸 bbox 안 목표 지점(0~1)."""
    x0, y0, x1, y1 = body.split()[3].getbbox()
    bw, bh = x1-x0, y1-y0
    w = wing.transpose(Image.FLIP_LEFT_RIGHT) if flip else wing
    s = (w_h*bh)/w.height
    w = w.resize((max(1, round(w.width*s)), max(1, round(w.height*s))), Image.LANCZOS)
    ax, ay = (w.width-1)*ax_r, (w.height-1)*ay_r
    pad = max(w.size)
    big = Image.new('RGBA', (w.width+2*pad, w.height+2*pad), (0,0,0,0))
    big.alpha_composite(w, (pad, pad))
    rot = big.rotate(angle, resample=Image.BICUBIC, center=(ax+pad, ay+pad))
    tx, ty = x0 + tx_r*bw, y0 + ty_r*bh
    ox, oy = round(tx-ax-pad), round(ty-ay-pad)
    layer = Image.new('RGBA', (CW, CH), (0,0,0,0))
    layer.alpha_composite(rot, (max(0,ox), max(0,oy)),
                          (max(0,-ox), max(0,-oy), rot.width, rot.height))
    return layer

def winged(cell, phase):
    """앞을 보고 앉거나 선 칸. 두 날개를 등 뒤에 얹는다."""
    body = _shrink(cell)
    x0, y0, x1, y1 = body.split()[3].getbbox()
    bw, bh = x1-x0, y1-y0
    ang = BASE + AMP*math.sin(2*math.pi*phase + math.pi/6)
    layer = Image.new('RGBA', (CW, CH), (0,0,0,0))
    for side in ('L', 'R'):
        tx_r = LX_R if side == 'L' else RX_R
        layer.alpha_composite(_place(body, FRONT[side], WH_R, 1.0 if side=='L' else 0.0, 1.0,
                                     tx_r, AY_R, ang if side=='L' else -ang))
    out = Image.new('RGBA', (CW, CH), (0,0,0,0))
    out.alpha_composite(layer); out.alpha_composite(body)
    return out

def winged_side(cell, phase, facing_right=True):
    """달리기·도약. 한쪽 날개를 어깨에 얹고 몸 앞에 그린다 — 뒤에 두면 꼬리에 가린다.
    좌우를 뒤집으면 날개 뿌리도 반대편으로 가므로 회전축을 같이 옮긴다."""
    body = _shrink(cell)
    ang  = 9*math.sin(2*math.pi*phase + math.pi/6)
    # 달리는 자세는 꼬리가 위로 크게 뻗어 bbox 위쪽이 꼬리 끝이 된다. 비율을 머리 기준으로
    # 잡으면 날개가 귀 옆에 붙는다. 뿌리를 등 한가운데(0.45)로 물리고, 눕히지 않고 30도 세운다 —
    # 눕히면 목덜미에 꽂아 놓은 것처럼 보이고 앞 칸에서는 머리를 덮는다.
    tx   = 0.45 if facing_right else 0.55
    axr  = 1.0  if facing_right else 0.0
    tilt = -30.0 if facing_right else 30.0
    layer = _place(body, SIDE, 0.45, axr, 1.0, tx, 0.52,
                   tilt + (ang if facing_right else -ang), flip=not facing_right)
    out = Image.new('RGBA', (CW, CH), (0,0,0,0))
    out.alpha_composite(body); out.alpha_composite(layer)
    return out

def winged_lying(cell, phase, wh, lx, rx, ty):
    """엎드리거나 자는 칸. 편 날개를 몸 뒤에 두어 좌우로 살짝 나오게 한다."""
    body = _shrink(cell)
    ang = BASE + AMP*math.sin(2*math.pi*phase + math.pi/6)
    layer = Image.new('RGBA', (CW, CH), (0,0,0,0))
    for side in ('L', 'R'):
        tx_r = lx if side == 'L' else rx
        layer.alpha_composite(_place(body, FRONT[side], wh, 1.0 if side=='L' else 0.0, 1.0,
                                     tx_r, ty, ang if side=='L' else -ang))
    out = Image.new('RGBA', (CW, CH), (0,0,0,0))
    out.alpha_composite(layer); out.alpha_composite(body)
    return out

def _edge_pixels(cell):
    """칸 네 변에 걸친 픽셀 수. 날개 끝이 잘렸는지 보는 값이다."""
    a = cell.split()[3]
    bands = [a.crop((0,0,CW,1)), a.crop((0,CH-1,CW,CH)),
             a.crop((0,0,1,CH)), a.crop((CW-1,0,CW,CH))]
    return sum(sum(1 for v in band.tobytes() if v > 8) for band in bands)

def build():
    base = Image.open(os.path.join(ASSETS, 'spritesheet.webp')).convert('RGBA')
    if base.size != (CW*COLS, CH*ROWS):
        sys.exit(f'기본 아틀라스 크기가 다르다: {base.size}')
    out = base.copy()
    edge = 0
    for r, kinds in PLAN.items():
        for c, k in enumerate(kinds):
            src = base.crop((c*CW, r*CH, (c+1)*CW, (r+1)*CH))
            if src.split()[3].getbbox() is None:
                continue
            ph = c/len(kinds)
            if   k == 'F': im = winged(src, ph)
            elif k == 'S': im = winged_side(src, ph, True)
            elif k == 'L': im = winged_side(src, ph, False)
            else:          im = winged_lying(src, ph, *LIE[r])
            edge += _edge_pixels(im)
            out.paste(im, (c*CW, r*CH))
    return out, edge

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--check', action='store_true', help='파일을 쓰지 않고 지금 것과 같은지만 본다')
    args = p.parse_args()
    out, edge = build()
    print(f'80칸 생성 · 칸 경계에 닿은 픽셀 {edge}개')
    target = os.path.join(ASSETS, 'spritesheet-angel.webp')
    with tempfile.TemporaryDirectory() as td:
        png = os.path.join(td, 'angel.png')
        out.save(png)
        webp = os.path.join(td, 'angel.webp')
        subprocess.run(['cwebp', '-lossless', '-exact', '-z', '9', png, '-o', webp],
                       check=True, capture_output=True)
        new = open(webp, 'rb').read()
        if args.check:
            old = open(target, 'rb').read() if os.path.exists(target) else b''
            if new == old:
                print('지금 파일과 같다')
                return 0
            print(f'다르다: 지금 {len(old)}바이트 · 다시 만든 것 {len(new)}바이트')
            return 1
        open(target, 'wb').write(new)
        print(f'썼다: {target} ({len(new)}바이트)')
    return 0

if __name__ == '__main__':
    sys.exit(main())
