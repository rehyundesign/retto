"""Restore the oversized third frame in Magical Heart's failed animation.

The failed animation uses source row 5.  Its third frame is a tall, seated
pose, but the dressed export exceeded the matching base Retto pose by 16%.
Keep its bottom baseline and center, while returning it to the source pose's
2x silhouette bounds.
"""

from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "assets/spritesheet.webp"
MAGICAL = ROOT / "assets/spritesheet-magical-heart.webp"
OUTPUT = Path(__file__).with_name("magical-heart-failed-frame-scale-fixed.png")
CELL_W, CELL_H = 448, 640
ROW, COLUMN = 5, 2


def main() -> None:
    original = Image.open(SOURCE).convert("RGBA")
    atlas = Image.open(MAGICAL).convert("RGBA")
    box = (COLUMN * CELL_W, ROW * CELL_H, (COLUMN + 1) * CELL_W, (ROW + 1) * CELL_H)
    cell = atlas.crop(box)
    sprite_bounds = cell.getchannel("A").getbbox()
    base = original.crop((COLUMN * 224, ROW * 320, (COLUMN + 1) * 224, (ROW + 1) * 320)).resize(
        (CELL_W, CELL_H), Image.Resampling.LANCZOS
    )
    base_bounds = base.getchannel("A").getbbox()
    if sprite_bounds is None or base_bounds is None:
        raise RuntimeError("Failed frame or matching base pose is blank")

    sprite = cell.crop(sprite_bounds)
    target_width = base_bounds[2] - base_bounds[0]
    target_height = base_bounds[3] - base_bounds[1]
    sprite.thumbnail((target_width, target_height), Image.Resampling.LANCZOS)
    repaired = Image.new("RGBA", cell.size, (0, 0, 0, 0))
    resized_bounds = sprite.getchannel("A").getbbox()
    if resized_bounds is None:
        raise RuntimeError("Resized failed frame is blank")
    x = round((base_bounds[0] + base_bounds[2] - resized_bounds[0] - resized_bounds[2]) / 2)
    y = base_bounds[3] - resized_bounds[3]
    repaired.alpha_composite(sprite, (x, y))
    atlas.paste(repaired, box)
    # WebP retains RGB below fully transparent pixels. Clear it before encoding
    # so the atlas cannot produce a coloured fringe on dark backgrounds.
    transparent = atlas.getchannel("A").point(lambda alpha: 255 if alpha == 0 else 0)
    atlas.paste((0, 0, 0, 0), mask=transparent)
    atlas.save(OUTPUT)


if __name__ == "__main__":
    main()
