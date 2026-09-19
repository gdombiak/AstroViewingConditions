from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SRC = ROOT.parent / "src"
# Git currently records this tree as Tests/parity (Phase 13 will make
# lowercase tests/parity unambiguous after the iOS Tests/ relocation).
PARITY = ROOT.parents[2] / "Tests" / "parity"
for path in (SRC, ROOT, PARITY):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))
