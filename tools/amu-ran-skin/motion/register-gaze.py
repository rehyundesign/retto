"""Active gaze path: original-pose complete character sources, version 2."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name('register-gaze-full-body.py')),run_name='__main__')
