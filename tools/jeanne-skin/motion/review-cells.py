from pathlib import Path
from PIL import Image, ImageDraw
import sys

root = Path(__file__).resolve().parent
args = sys.argv[1:]
production = '--production' in args
args = [arg for arg in args if arg != '--production']
source_root = root / ('production-raw' if production else 'raw')
for state in args:
    for theme, background, foreground in [('dark', '#20212d', 'white'), ('white', '#faf8f3', '#29232b')]:
        board = Image.new('RGB', (896, 1360), background)
        draw = ImageDraw.Draw(board)
        for frame in range(16):
            source = source_root / f'{state}-{frame:02}.png'
            if not source.exists():
                continue
            image = Image.open(source).convert('RGBA')
            image = image.resize((224, 320), Image.Resampling.LANCZOS)
            x, y = (frame % 4) * 224, (frame // 4) * 340
            board.paste(image, (x, y), image)
            draw.text((x + 8, y + 322), f'{state} {frame:02}', fill=foreground)
        board.save(root / 'review' / f"{state}{'-production' if production else ''}-{theme}.jpg", quality=96)
