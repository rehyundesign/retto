"""토끼 스킨 아틀라스를 만든다.

세 단계로 나눠 부른다. 한 단계가 끝날 때마다 눈으로 확인하고 다음으로 넘어간다.

    grid  <묶음>                     생성에 넣을 격자 PNG 를 만든다
    cut   <묶음> <생성물>             크로마키를 빼고 칸으로 자른다
    atlas                            자른 칸을 기본 아틀라스 자리에 되돌려 붙인다

    halfgrid <행> <시작칸> <끝칸>      한 행의 일부만 2열 격자로 만든다 (칸당 픽셀 4배)
    halfcut  <행> <시작칸> <끝칸> <생성물>

    cellgrid <행> <칸>                한 칸만 만든다 (시선 행 전용)
    cellcut  <행> <칸> <생성물>

`dress.py` 가 격자 만들기와 되돌리기를 갖고 있고 여기서는 그것을 부른다.
꿀벌·달 고양이 스킨과 같은 순서다 — 옷은 자세마다 형태가 달라져 레이어 합성이 안 되므로
자세 묶음마다 격자로 한 번에 입힌다.
"""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dress

HERE = os.path.dirname(os.path.abspath(__file__))
KEY = (3, 105, 243)          # 크로마키 파랑 #0369F3. 토끼 옷은 분홍이라 파란 키로 안전하다
GRID_COLS = 4

# 모델이 받는 비율은 정해진 목록뿐이라, 격자를 그 비율에 맞춰 오른쪽·아래로만 채운다.
# 가운데로 채우면 칸 자리가 밀려 자를 때 어긋난다. 안 맞추면 가로가 5% 눌린 채 생성된다.
ASPECT = {2: (16, 9), 3: (5, 4)}

# ⚠️ 토끼 귀가 높아 머리 위 여백을 꿀벌 스킨보다 크게 잡는다.
# 기본값(CAT_H 380 · FOOT_PAD 50)이면 여백이 50px 뿐이라 윗줄 귀가 이미지 밖에서 잘린다.
# 실제로 한 번 잘렸다 — 칸을 작게 넣어 머리 위를 145px 로 벌린다.
dress.CAT_H = 290
dress.FOOT_PAD = 45

# 묶음 이름 -> 기본 아틀라스의 (행, 쓰는 칸 수)
# 행 2 는 행 1 의 좌우 반전이라 생성하지 않는다 (기본 아틀라스에서 평균차 0.0 으로 확인).
BATCHES = {
    'idle':   [(0, 7)],
    'run':    [(1, 8)],
    'wave':   [(3, 4), (4, 5)],
    'fail':   [(5, 8)],
    'sit':    [(6, 6), (7, 6)],
    'sleep':  [(8, 6), (11, 6)],
    'gaze9':  [(9, 8)],
    'gaze10': [(10, 8)],
}


def path(*p):
    return os.path.join(HERE, *p)


def canvas(n):
    """묶음 칸 수 -> (격자 크기, 채운 크기, 비율 문자열, 격자 행 수)"""
    rows = (n + GRID_COLS - 1) // GRID_COLS
    w, h = dress.SLOT_W * GRID_COLS, dress.SLOT_H * rows
    aw, ah = ASPECT[rows]
    pw, ph = max(w, round(h * aw / ah)), max(h, round(w * ah / aw))
    # 한쪽만 늘려 비율을 맞춘다. 둘 다 늘리면 비율이 다시 어긋난다.
    if pw / ph > aw / ah:
        ph = round(pw * ah / aw)
    else:
        pw = round(ph * aw / ah)
    return (w, h), (pw, ph), f"{aw}:{ah}", rows


def unkey(img, tol=70, soft=40):
    """평평한 파란 배경을 알파로 바꾼다.

    거리 기반이라 목록에 없는 파랑 색조도 같이 빠진다. 잔광(despill)은 반투명한
    가장자리에만 건다 — 안쪽까지 걸면 고양이의 파란 눈에서 파랑이 빠진다.
    """
    a = np.array(img.convert('RGB'), dtype=np.float32)
    d = np.sqrt(((a - np.array(KEY, dtype=np.float32)) ** 2).sum(axis=2))
    alpha = np.clip((d - tol) / soft, 0, 1)

    edge = (alpha > 0) & (alpha < 1)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    cap = np.maximum(r, g)
    spill = edge & (b > cap)
    b[spill] = cap[spill]

    out = np.dstack([a, alpha * 255]).astype(np.uint8)
    return Image.fromarray(out, 'RGBA')


def largest_blob(cell, min_frac=0.02):
    """칸에서 가장 큰 덩어리만 남긴다.

    격자를 자를 때 옆 칸이 얇게 걸려 들어온다. 그걸 두고 되돌리면 bbox 가 부풀어
    고양이가 칸 밖으로 밀린다 — 달 고양이 스킨에서 아홉 칸이 반쯤 잘렸던 사고다.
    """
    a = np.array(cell)
    mask = a[..., 3] > 8
    lab, n = ndimage.label(mask)
    if n <= 1:
        return cell, n
    sizes = ndimage.sum(mask, lab, range(1, n + 1))
    keep = int(np.argmax(sizes)) + 1
    dropped = int((sizes < sizes[keep - 1] * min_frac).sum())
    a[..., 3] = np.where(lab == keep, a[..., 3], 0)
    return Image.fromarray(a, 'RGBA'), n - 1


SIDE_PAD, TOP_PAD = 36, 145
MARGIN = 2          # 칸 가장자리에 닿지 않게 남기는 여유. 반올림으로 1px 넘던 것을 막는다


def make_grid(items, cols, size):
    """칸마다 고양이를 넣되 폭과 높이를 **둘 다** 슬롯 안에 맞춘다.

    ⚠️ `dress.make_grid` 는 높이만 맞춘다. 누운 자세는 옆으로 길어서 그러면 폭이 슬롯을
    넘고, 격자에서 옆 칸과 붙는다. 붙은 채로 생성하면 모델이 그 둘을 한 덩어리로 보고
    통째로 키워 버린다 — `sleep` 에서 실제로 났다 (누운 여섯 칸이 가로로 다 겹쳤다).
    """
    max_w, max_h = dress.SLOT_W - 2 * SIDE_PAD, dress.SLOT_H - dress.FOOT_PAD - TOP_PAD
    g = Image.new('RGB', size, KEY)
    for i, (_, _, cell) in enumerate(items):
        bb = cell.split()[3].getbbox()
        cat = cell.crop(bb)
        s = min(max_h / cat.height, max_w / cat.width)
        nw, nh = round(cat.width * s), round(cat.height * s)
        cat = cat.resize((nw, nh), Image.LANCZOS)
        ox, oy = (i % cols) * dress.SLOT_W, (i // cols) * dress.SLOT_H
        g.paste(cat, (ox + (dress.SLOT_W - nw) // 2,
                      oy + dress.SLOT_H - dress.FOOT_PAD - nh), cat)
    return g


def cmd_grid(batch):
    items = dress.cellsOf(BATCHES[batch])
    (w, h), (pw, ph), aspect, rows = canvas(len(items))
    out = path(f'grid-{batch}.png')
    make_grid(items, GRID_COLS, (pw, ph)).save(out)
    print(f"{batch}: {len(items)}칸 · {rows}행 x {GRID_COLS}열 · {w}x{h} -> {pw}x{ph} ({aspect})")
    print(f"  {out}")


def cmd_cut(batch, gen):
    items = dress.cellsOf(BATCHES[batch])
    _, want, _, _ = canvas(len(items))

    g = Image.open(gen)
    if g.size != want:
        print(f"  생성물 {g.size} -> 격자 규격 {want} 로 맞춘다")
        g = g.resize(want, Image.LANCZOS)
    g = unkey(g)

    out_dir = path(f'gen-{batch}')
    os.makedirs(out_dir, exist_ok=True)
    for i in range(len(items)):
        ox, oy = (i % GRID_COLS) * dress.SLOT_W, (i // GRID_COLS) * dress.SLOT_H
        cell = g.crop((ox, oy, ox + dress.SLOT_W, oy + dress.SLOT_H))
        cell, strays = largest_blob(cell)
        area = int((np.array(cell)[..., 3] > 8).sum())
        cell.save(os.path.join(out_dir, f'k-{i}.png'))
        print(f"  k-{i}: 알파 {area//1000}k · 지운 조각 {strays}")
    print(f"{batch}: {len(items)}칸 -> {out_dir}/")


# 발로 맞출 수 없는 자리. 발이 떠 있거나(달리기) 접혀 있어(누움) 발 폭이 자세를 못 나타낸다.
# 꿀벌·달 고양이 스킨 설명서가 적어 둔 것과 같다 — 이 자리는 bbox 로 맞춘다.
BBOX_ROWS = {1, 2, 11}
BBOX_CELLS = {(5, 3), (5, 5), (5, 7)}


def measure(items, gen_dir, log):
    """되돌리기에 필요한 값을 칸마다 잰다. 배율은 아직 정하지 않는다.

    격자에 넣을 때 쓴 배율(`expect`)을 그대로 뒤집는 것이 기본이다. 기본 아틀라스는 행마다
    고양이 크기가 달라서(행 4 는 행 3 보다 12% 작다) 칸마다 다른 배율로 넣었고, 되돌릴 때
    다시 재면 그 차이가 지워진다.

    모델이 얼마나 키워 그렸는지(`drift`)만 따로 모아 두고, **보정값은 묶음이 아니라 전체에서
    하나로 정한다** — `cmd_atlas` 가 한다. ⚠️ 묶음마다 따로 구하면 묶음 사이의 크기 관계가
    깨진다. 실제로 달리기 0.910·시선9 1.012 로 11% 벌어져서, 달릴 때 고양이가 줄어 보였다.
    폭으로 재는 이유는 토끼 귀가 높이만 늘리기 때문이다 — 높이로 재면 몸이 그만큼 작아진다.
    """
    max_w, max_h = dress.SLOT_W - 2 * SIDE_PAD, dress.SLOT_H - dress.FOOT_PAD - TOP_PAD
    for i, (r, c, cell) in enumerate(items):
        gi = Image.open(os.path.join(gen_dir, f'k-{i}.png')).convert('RGBA')
        gbb, bbb = gi.split()[3].getbbox(), cell.split()[3].getbbox()
        expect = 1 / min(max_h / (bbb[3] - bbb[1]), max_w / (bbb[2] - bbb[0]))
        drift = ((bbb[2] - bbb[0]) / (gbb[2] - gbb[0])) / expect

        if r in BBOX_ROWS or (r, c) in BBOX_CELLS:
            why = 'bbox 기준점'          # 발이 뜨거나 접혀 발 자리를 못 쓴다
            gax, gay = (gbb[0] + gbb[2]) / 2, gbb[3]
            bax, bay = (bbb[0] + bbb[2]) / 2, bbb[3]
        else:
            why = '발 기준점'
            (_, gax, gay), (_, bax, bay) = dress.feet(gi), dress.feet(cell)
        log.append([r, c, expect, drift, why, gi, gbb, None, gax, gay, bax, bay])


def compose(log, sheet, k):
    """되돌리기 결과를 배율 k 를 곱해 아틀라스에 붙인다. 기준점은 발 자리라 바닥선이 안 움직인다."""
    for r, c, _, _, _, gi, gbb, s0, gax, gay, bax, bay in log:
        s = s0 * k
        crop = gi.crop(gbb)
        nw, nh = round(crop.width * s), round(crop.height * s)
        big = crop.resize((nw, nh), Image.LANCZOS)
        new = Image.new('RGBA', (dress.CW, dress.CH), (0, 0, 0, 0))
        ox, oy = round(bax - (gax - gbb[0]) * s), round(bay - (gay - gbb[1]) * s)
        new.alpha_composite(big, (max(0, ox), max(0, oy)),
                            (max(0, -ox), max(0, -oy), nw, nh))
        sheet.paste(new, (c * dress.CW, r * dress.CH))


def fit_scale(log):
    """칸 밖으로 넘치지 않는 가장 큰 공통 배율.

    ⚠️ 토끼 귀가 기본 고양이의 머리 위 여백보다 높다. 발을 맞추면 몸 크기는 맞지만 귀가
    칸 위에서 잘린다 — 그대로 두면 17칸이 잘렸다. 칸마다 따로 줄이면 재생 중에 크기가
    흔들리므로 **전체에 같은 배율**을 곱한다.
    """
    ks = []
    for r, c, _, _, _, gi, gbb, s, gax, gay, bax, bay in log:
        up = (gay - gbb[1]) * s                      # 기준점 위로 뻗는 높이
        left = (gax - gbb[0]) * s
        right = (gbb[2] - gax) * s
        ks += [(bay - MARGIN) / up if up else 1.0,
               (bax - MARGIN) / left if left else 1.0,
               (dress.CW - bax - MARGIN) / right if right else 1.0]
    return min(1.0, min(ks))


# 한 행을 4칸씩 나눠 만들 때 쓴다. 격자가 2열이라 칸 하나가 받는 픽셀이 4배가 된다.
# ⚠️ 시선 행(9·10)은 이걸로 만들어야 고개 각도가 제대로 따라온다 — 8칸을 한 장에 넣으면
# 모델이 각도를 뭉개고 대부분 정면을 보게 그린다. 4칸씩 나누니 여덟 칸 모두 돌았다.
HALF_COLS = 2


def half_size():
    w, h = dress.SLOT_W * HALF_COLS, dress.SLOT_H * 2
    return (max(w, h), h)          # 1:1 로 맞춘다


def cmd_halfgrid(row, a, b):
    s = dress.base()
    items = [(row, c, s.crop((c*dress.CW, row*dress.CH, (c+1)*dress.CW, (row+1)*dress.CH)))
             for c in range(a, b)]
    out = path(f'grid-r{row}h{a}.png')
    make_grid(items, HALF_COLS, half_size()).save(out)
    print(f"행 {row} c{a}~c{b-1}: {b-a}칸 · {HALF_COLS}열 -> {out} {half_size()} (1:1)")


def cmd_halfcut(row, a, b, gen, batch):
    g = Image.open(gen)
    if g.size != half_size():
        print(f"  생성물 {g.size} -> {half_size()} 로 맞춘다")
        g = g.resize(half_size(), Image.LANCZOS)
    g = unkey(g)
    out_dir = path(f'gen-{batch}')
    os.makedirs(out_dir, exist_ok=True)
    for i in range(b - a):
        ox, oy = (i % HALF_COLS)*dress.SLOT_W, (i // HALF_COLS)*dress.SLOT_H
        cell = g.crop((ox, oy, ox+dress.SLOT_W, oy+dress.SLOT_H))
        cell, strays = largest_blob(cell)
        idx = a + i                       # 묶음 안 칸 번호 = 행 안 칸 번호
        cell.save(os.path.join(out_dir, f'k-{idx}.png'))
        print(f"  k-{idx}: 알파 {int((np.array(cell)[...,3]>8).sum())//1000}k · 지운 조각 {strays}")


# 한 칸씩 만들 때. 시선 행은 몸이 정면인 채 고개만 돌아서, 여러 칸을 한 장에 넣으면
# 모델이 후드를 몸 방향에 고정한 채 얼굴만 돌려 넣는다. 한 칸씩이어야 각도가 따라온다.
def cell_size():
    return (max(dress.SLOT_W, dress.SLOT_H),) * 2      # 480x480, 1:1


def cmd_cellgrid(row, col):
    s = dress.base()
    item = [(row, col, s.crop((col*dress.CW, row*dress.CH, (col+1)*dress.CW, (row+1)*dress.CH)))]
    out = path(f'grid-r{row}c{col}.png')
    make_grid(item, 1, cell_size()).save(out)
    print(f"행 {row} c{col} -> {out} {cell_size()}")


def cmd_cellcut(row, col, gen, batch):
    g = Image.open(gen)
    if g.size != cell_size():
        g = g.resize(cell_size(), Image.LANCZOS)
    g = unkey(g)
    cell = g.crop((0, 0, dress.SLOT_W, dress.SLOT_H))
    cell, strays = largest_blob(cell)
    out_dir = path(f'gen-{batch}')
    os.makedirs(out_dir, exist_ok=True)
    cell.save(os.path.join(out_dir, f'k-{col}.png'))
    a = np.array(cell)[..., 3] > 8
    print(f"  r{row}c{col}: 알파 {int(a.sum())//1000}k · 지운 조각 {strays}")


def cmd_atlas():
    sheet = Image.new('RGBA', (1792, 2880), (0, 0, 0, 0))
    log = []
    for batch, spec in BATCHES.items():
        d = path(f'gen-{batch}')
        if not os.path.isdir(d):
            sys.exit(f"아직 자르지 않은 묶음이 있다: {batch}")
        measure(dress.cellsOf(spec), d, log)

    # ⚠️ 보정값은 전체에서 하나로 정한다. 묶음마다 정하면 묶음 사이 크기가 어긋난다.
    drift = sorted(x[3] for x in log)
    mid = drift[len(drift) // 2]
    for x in log:
        x[7] = x[2] * mid
    print(f"되돌린 칸 {len(log)} · 공통 보정값 {mid:.3f} "
          f"(묶음별로 재면 {drift[0]:.3f}~{drift[-1]:.3f} 로 벌어진다)")
    print(f"  발 기준점 {sum(1 for x in log if x[4]=='발 기준점')} · "
          f"bbox 기준점 {sum(1 for x in log if x[4]!='발 기준점')}")

    k = fit_scale(log)
    print(f"공통 배율 {k:.4f} (칸을 넘지 않는 가장 큰 값)")
    compose(log, sheet, k)

    # 행 2 는 행 1 을 좌우로 뒤집어 만든다. 기본 아틀라스가 그렇게 돼 있다.
    band = sheet.crop((0, 1 * dress.CH, 1792, 2 * dress.CH))
    sheet.paste(band.transpose(Image.FLIP_LEFT_RIGHT), (0, 2 * dress.CH))

    out = path('atlas.png')
    sheet.save(out)
    print(f"아틀라스 -> {out} {sheet.size[0]}x{sheet.size[1]}")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    cmd = sys.argv[1]
    if cmd == 'grid':
        cmd_grid(sys.argv[2])
    elif cmd == 'cut':
        cmd_cut(sys.argv[2], sys.argv[3])
    elif cmd == 'atlas':
        cmd_atlas()
    elif cmd == 'cellgrid':
        cmd_cellgrid(int(sys.argv[2]), int(sys.argv[3]))
    elif cmd == 'cellcut':
        row, col = int(sys.argv[2]), int(sys.argv[3])
        cmd_cellcut(row, col, sys.argv[4], f'gaze{row}')
    elif cmd == 'halfgrid':
        cmd_halfgrid(int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]))
    elif cmd == 'halfcut':
        row, a, b = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
        cmd_halfcut(row, a, b, sys.argv[5], f'gaze{row}')
    else:
        sys.exit(__doc__)
