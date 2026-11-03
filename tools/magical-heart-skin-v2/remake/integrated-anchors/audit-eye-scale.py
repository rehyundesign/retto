"""Diagnostic eye-spacing comparison; does not approve face or body registration."""
from pathlib import Path
from collections import deque
import json
import math
import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent
REF = ROOT.parent / 'reference'
def eyes(path):
    pixels = np.array(Image.open(path).convert('RGBA'), dtype=np.int16)
    r, g, b, alpha = [pixels[:, :, index] for index in range(4)]
    mask = (alpha > 220) & (b > r * 1.12) & (b > g * 1.05) & (r < 160)
    mask[530:, :] = False
    visited = np.zeros(mask.shape, dtype=bool)
    groups = []
    for y, x in zip(*np.where(mask)):
        if visited[y, x]:
            continue
        queue = deque([(int(x), int(y))]); points = []
        visited[y, x] = True
        while queue:
            px, py = queue.popleft(); points.append((px, py))
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)]:
                nx, ny = px + dx, py + dy
                if 0 <= nx < mask.shape[1] and 0 <= ny < mask.shape[0] and mask[ny, nx] and not visited[ny, nx]:
                    visited[ny, nx] = True; queue.append((nx, ny))
        if len(points) >= 10:
            groups.append({'pixels': len(points), 'center': [sum(p[0] for p in points) / len(points), sum(p[1] for p in points) / len(points)]})
    candidates = sorted(groups, key=lambda group: group['pixels'], reverse=True)[:2]
    if len(candidates) != 2:
        return {'status': 'not measurable', 'components': candidates}
    candidates.sort(key=lambda group: group['center'][0])
    delta = [candidates[1]['center'][i] - candidates[0]['center'][i] for i in range(2)]
    return {'status': 'diagnostic only; manual eye-region confirmation required', 'components': candidates,
            'distance': math.hypot(*delta)}

manifest = json.loads((ROOT / 'manifest.json').read_text())
aliases = {'waving-key-10': 'waving-anchor', 'failed-key-10': 'failed-anchor', 'waiting-key-10': 'waiting-anchor'}
records = []
for item in manifest['anchors']:
    reference = REF / (aliases.get(item['id'], item['id']) + '-original.png')
    candidate = ROOT / 'cells' / (item['id'] + '.png')
    record = {'id': item['id'], 'reference': eyes(reference), 'candidate': eyes(candidate),
              'registration_approved': False}
    if 'distance' in record['reference'] and 'distance' in record['candidate']:
        record['eye_spacing_ratio'] = record['candidate']['distance'] / record['reference']['distance']
    records.append(record)
(ROOT / 'eye-scale-diagnostic.json').write_text(json.dumps(records, indent=2))
print(json.dumps([{'id': r['id'], 'eye_spacing_ratio': round(r.get('eye_spacing_ratio', 0), 3), 'registration_approved': False} for r in records]))
