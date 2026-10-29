"""Render independent anchor sources at runtime scale, without changing sources."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import hashlib
import json

root = Path(__file__).resolve().parent
manifest = json.loads((root / 'production-map.json').read_text())
font = ImageFont.truetype('/System/Library/Fonts/AppleSDGothicNeo.ttc', 13)
report = []
for theme, background in [('light', '#fffdfa'), ('dark', '#23232d')]:
    board = Image.new('RGB', (4 * 240, 4 * 352), background)
    draw = ImageDraw.Draw(board)
    for index, anchor in enumerate(manifest['static_anchors']):
        x, y = (index % 4) * 240, (index // 4) * 352
        path = root / anchor.get('registered_source', anchor.get('source', 'missing'))
        draw.text((x + 8, y + 6), anchor['id'] + ' / ' + anchor['sequence'], font=font,
                  fill='#51444d' if theme == 'light' else '#f0e7ee')
        if not path.is_file():
            draw.text((x + 8, y + 30), 'pending', font=font, fill='#b85b7a')
            continue
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        source = Image.open(path).convert('RGBA')
        cell = source.copy()
        cell.thumbnail((224, 320), Image.Resampling.LANCZOS)
        board.paste(cell, (x + 8 + (224 - cell.width) // 2,
                          y + 28 + (320 - cell.height) // 2), cell)
        assert hashlib.sha256(path.read_bytes()).hexdigest() == digest
        if theme == 'light':
            report.append({'id': anchor['id'], 'source': str(path.relative_to(root)),
                           'sha256': digest, 'size': list(source.size),
                           'alpha_bounds': source.getchannel('A').getbbox(),
                           'rgba': source.mode == 'RGBA',
                           'registration': 'not certified by this rendering check'})
    board.save(root / f'static-anchors-{theme}-1x.png')
(root / 'static-anchor-render-audit.json').write_text(
    json.dumps({'sources': report, 'display': [224, 320],
                'source_hashes_preserved': True, 'production_ready': False}, indent=2) + '\n')
print(f'Rendered {len(report)} independent anchors on light/dark backgrounds; sources unchanged.')
