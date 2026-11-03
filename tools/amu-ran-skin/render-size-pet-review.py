"""Review registered cats plus the unchanged, separately placed Ran layer."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib
import json

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'production-map.json').read_text())
version = manifest.get('size_registration', {}).get('version', 'v1')
ran_path = root / 'reference/ran-sculpted-v10-source.png'
ran_hash = hashlib.sha256(ran_path.read_bytes()).hexdigest()
ran = Image.open(ran_path).convert('RGBA')
ran = ran.crop(ran.getchannel('A').point(lambda a: 255 if a > 8 else 0).getbbox())
ran.thumbnail((90, 90), Image.Resampling.LANCZOS)
labels = ['기본', '작업', '살펴보기', '대기', '놀람', '변신', '점프 준비', '잠',
          '오른쪽 걷기', '왼쪽 걷기', '돌아보기', '응원', '살짝 손 뻗기', '완료', '점프', '회복']
positions = {'A08': (340,350), 'A09': (124,368), 'A10': (300,350), 'A15': (360,210)}
positions.update(manifest.get('size_registration', {}).get('ran_positions_2x', {}))
font = ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', 14)
records = []
for theme, background, ink in [('light','#fffdfa','#51444d'),('dark','#23232d','#f0e7ee')]:
    board = Image.new('RGB', (960,1408), background)
    draw = ImageDraw.Draw(board)
    scenes = {}
    for i, anchor in enumerate(manifest['static_anchors']):
        path = root / anchor['registered_source']
        before = hashlib.sha256(path.read_bytes()).hexdigest()
        scene = Image.open(path).convert('RGBA')
        assert scene.size == (448,640)
        position = positions.get(anchor['id'], (360,282) if anchor['id'] in ['A06','A07','A14'] else (360,330))
        scene.alpha_composite(ran, position)
        x,y = i%4*240, i//4*352
        draw.text((x+8,y+6), labels[i], font=font, fill=ink)
        scene = scene.resize((224,320), Image.Resampling.LANCZOS)
        scenes[anchor['id']] = scene.copy()
        board.paste(scene,(x+8,y+28),scene)
        assert hashlib.sha256(path.read_bytes()).hexdigest() == before
        if theme == 'light':
            records.append({'id':anchor['id'], 'character':anchor['registered_source'],
                            'character_sha256':before, 'ran_position_2x':position})
    board.save(root/f'static-size-pet-review-{version}-{theme}.png')
    if version == 'v2':
        focus = Image.new('RGB', (720,704), background)
        fd = ImageDraw.Draw(focus)
        for i,(name,label) in enumerate([('A01','교복 · 기본'),('A06','변신 · 기본'),('A07','변신 · 점프 준비'),
                                          ('A02','교복 · 앞발 들기'),('A14','변신 · 완료'),('A15','변신 · 점프')]):
            x,y=i%3*240,i//3*352
            fd.text((x+8,y+6), label,font=font,fill=ink)
            focus.paste(scenes[name],(x+8,y+28),scenes[name])
        focus.save(root/f'heart-school-size-comparison-{version}-{theme}.png')
assert hashlib.sha256(ran_path.read_bytes()).hexdigest() == ran_hash
(root/f'static-size-pet-review-{version}.json').write_text(json.dumps({'stage':'static-size-review',
    'animated':False, 'installed':False, 'ran_source_sha256':ran_hash,
    'ran_size_2x':ran.size, 'unchanged_character_and_companion_sources':True,
    'records':records},indent=2)+'\n')
print('Rendered all 16 registered static pets at 1x, fixed Ran size; independent sources unchanged.')
