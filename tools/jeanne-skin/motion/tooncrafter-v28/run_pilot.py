"""Run the official ToonCrafter demo on two complete Jeanne Retto cells.

This writes experimental RGB output only. It does not replace v27 assets.
"""
from pathlib import Path
import argparse
import json
import time
from gradio_client import Client, handle_file

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--steps', type=int, default=40)
args = parser.parse_args()
state = {"model": "Doubiiu/tooncrafter", "phase": "connecting", "generatedFrames": 0, "steps": args.steps}

def checkpoint(**fields):
    state.update(fields)
    (ROOT / "execution.json").write_text(json.dumps(state, indent=2))
    print(json.dumps(fields), flush=True)

try:
    client = Client("Doubiiu/tooncrafter", download_files=str(ROOT / "output"), verbose=False)
    checkpoint(phase="submitting")
    job = client.submit(
        image=handle_file(str(ROOT / "input/start.png")),
        prompt="A fluffy blue-eyed cat wearing a red and ivory magical Jeanne costume slowly lifts its left forepaw to touch the pink winged pendant. The little green-haired winged fairy stays beside its right ear, softly fluttering. Fixed camera, fixed cat and fairy scale, grounded feet, flowing short crimson silk and ivory feathers. Plain warm white background.",
        steps=args.steps, cfg_scale=7.5, eta=1.0, fs=10, seed=123,
        image2=handle_file(str(ROOT / "input/end.png")),
        api_name="/get_image",
    )
    checkpoint(phase="queued")
    previous = None
    while not job.done():
        current = str(job.status().code)
        if current != previous:
            checkpoint(phase=current)
            previous = current
        time.sleep(5)
    result = job.result()
    checkpoint(phase="generated", result=result)
except Exception as exc:
    checkpoint(phase="failed", errorType=type(exc).__name__, error=str(exc))
    raise SystemExit(1)
