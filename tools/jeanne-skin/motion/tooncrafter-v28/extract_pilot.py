"""Extract actual ToonCrafter output; never substitute existing v27 images.

RGB frames are experimental. No transparent production sprites are claimed.
"""
from pathlib import Path
from PIL import Image, ImageDraw
import json
import subprocess

root = Path(__file__).resolve().parent
state = json.loads((root / "execution.json").read_text())
if state.get("phase") != "generated":
    raise SystemExit("No generated ToonCrafter output yet; extraction skipped")
result = state["result"]
if isinstance(result, dict):
    video = result.get("video")
    if isinstance(video, dict):
        video = video.get("path")
elif isinstance(result, str):
    video = result
else:
    raise SystemExit("Inspect unknown result schema before extracting")
video = Path(video)
assert video.is_file(), video
frames_dir = root / "output/frames-rgb"
frames_dir.mkdir(exist_ok=True)
subprocess.run(["ffmpeg", "-v", "error", "-i", str(video), "-vsync", "0", str(frames_dir / "%02d.png")], check=True)
files = sorted(frames_dir.glob("[0-9][0-9].png"))
assert len(files) == 16, f"Unexpected decoded frame count: {len(files)}"
frames = []
for file in files:
    im = Image.open(file).convert("RGB")
    assert im.size == (512, 320), im.size
    # Remove the input's fixed side padding; no per-frame bounding-box fit.
    frames.append(im.crop((144, 0, 368, 320)))
board = Image.new("RGB", (896, 1280), "#fffdf8")
for i, im in enumerate(frames):
    im.save(frames_dir / f"cell-{i:02}.png")
    board.paste(im, ((i % 4) * 224, (i // 4) * 320))
board.save(root / "output/review-rgb.png")
frames[0].save(root / "output/pilot-natural.gif", save_all=True, append_images=frames[1:], duration=[120,130]*8, loop=0, disposal=2)
frames[0].save(root / "output/pilot-fast.gif", save_all=True, append_images=frames[1:], duration=[40,40,40,30]*4, loop=0, disposal=2)
decoded = Image.open(root / "output/pilot-fast.gif")
assert decoded.n_frames == 16
durations=[]
for i in range(16):
    decoded.seek(i);durations.append(decoded.info['duration'])
assert sum(durations)==600
(root / "output/extraction.json").write_text(json.dumps({"video":str(video),"frames":16,"transparent":False,"cell":[224,320],"fixedCrop":[144,0,368,320],"fastDurationMs":600,"naturalDurationMs":2000,"status":"experimental segment; not a complete loop or production replacement"},indent=2))
print("Extracted actual16 RGB frames and two GIF timing variants; v27 unchanged")
