"""Compose a design-only board. Never use this board as an atlas or pose source."""
from pathlib import Path
import argparse
import hashlib
import json
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent
FONT = '/System/Library/Fonts/AppleSDGothicNeo.ttc'
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--heart-source', default='anchors/idle-heart-source.png')
parser.add_argument('--output', default='costume-preview.png')
args = parser.parse_args()
output = ROOT / args.output

def font(size):
    return ImageFont.truetype(FONT, size)

def trimmed(path):
    image = Image.open(path).convert('RGBA')
    bounds = image.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox()
    if bounds is None:
        raise ValueError(f'Empty design source: {path}')
    return image.crop(bounds)

board = Image.new('RGBA', (1100, 740), '#fff8fa')
draw = ImageDraw.Draw(board)
draw.text((52, 30), '아무 · 란', fill='#3b2932', font=font(38))
draw.text((54, 83), '교복과 하트 변신 의상 시안', fill='#8f6b7d', font=font(20))
ran_source = ROOT / 'reference/ran-neutral-source.png'
ran = trimmed(ran_source)
ran.thumbnail((90, 90), Image.Resampling.LANCZOS)
sources = []
for x, label, subtitle, source in [
    (40, '평소 · 교복', '검정 재킷  /  빨간 넥타이  /  체크무늬', ROOT / 'anchors/idle-school-source.png'),
    (570, '완료 · 하트 변신', '하트 선캡  /  분홍 응원복  /  란의 응원', ROOT / args.heart_source),
]:
    draw.rounded_rectangle((x, 130, x + 490, 643), radius=25, fill='#ffffff', outline='#efdce5', width=2)
    draw.text((x + 27, 151), label, fill='#763e59', font=font(25))
    draw.text((x + 27, 192), subtitle, fill='#967f8b', font=font(15))
    cat = trimmed(source)
    # Display-only uniform scaling. Registration must be checked on independent cells.
    height = 330
    width = round(cat.width * height / cat.height)
    cat = cat.resize((width, height), Image.Resampling.LANCZOS)
    board.alpha_composite(cat, (x + 74, 273))
    board.alpha_composite(ran, (x + 370, 300))
    draw.text((x + 27, 613), '의상 비교용 · 원본 크기 검증 전', fill='#ad909e', font=font(14))
    sources.append({'path': str(source.relative_to(ROOT)), 'sha256': hashlib.sha256(source.read_bytes()).hexdigest()})
draw.text((54, 667), '현재는 정적 후보입니다. 애니메이션 제작과 앱 적용은 아직 완료되지 않았습니다.', fill='#795f6e', font=font(19))
draw.text((54, 701), '얼굴·몸 비율과 원본 위치 검증을 통과한 뒤 개별 동작을 제작합니다.', fill='#a28795', font=font(15))
board.convert('RGB').save(output)
provenance = ROOT / ('preview-provenance.json' if args.output == 'costume-preview.png' else output.stem + '-provenance.json')
provenance.write_text(json.dumps({
    'kind': 'design-only-board', 'production_ready': False,
    'not_an_atlas_source': True, 'display_height_not_registration': 330,
    'sources': sources,
    'ran_sha256': hashlib.sha256(ran_source.read_bytes()).hexdigest(),
}, indent=2) + '\n')
print('Created design-only board: ' + str(output))
