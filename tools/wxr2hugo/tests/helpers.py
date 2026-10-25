"""Shared test helpers. Stdlib only; fixtures are synthetic."""

import base64
import hashlib
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

TOOL_DIR = Path(__file__).resolve().parent.parent
REPO = TOOL_DIR.parent.parent
FIXTURES = Path(__file__).resolve().parent / "fixtures"
CONVERT = TOOL_DIR / "convert.py"

# A valid 1x1 PNG.
PNG = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/"
    "iZk9HQAAAABJRU5ErkJggg=="
)


def load_module(name):
    spec = importlib.util.spec_from_file_location(
        "wxr2hugo_" + name, TOOL_DIR / (name + ".py")
    )
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def scratch():
    """A scratch directory outside the repository (the tool refuses in-repo paths)."""
    path = Path(tempfile.mkdtemp(prefix="wxr2hugo-test-")).resolve()
    assert REPO not in path.parents
    return path


def only_items(fixture, post_ids):
    """The fixture text with every <item> whose post_id is not listed removed."""
    text = (FIXTURES / fixture).read_text(encoding="utf-8")

    def keep(match):
        block = match.group(0)
        found = re.search(r"<wp:post_id>(\d+)</wp:post_id>", block)
        return block if found and found.group(1) in post_ids else ""

    return re.sub(r"<item>.*?</item>\n?", keep, text, flags=re.S)


def make_media(root):
    """A media tree holding 2023/02/pic.png."""
    target = Path(root) / "uploads" / "2023" / "02"
    target.mkdir(parents=True)
    (target / "pic.png").write_bytes(PNG)
    return Path(root) / "uploads"


def run(args, cwd=None):
    """Run the CLI exactly as documented: python3 -I convert.py ..."""
    return subprocess.run(
        [sys.executable, "-I", str(CONVERT)] + [str(a) for a in args],
        capture_output=True,
        text=True,
        cwd=cwd or tempfile.gettempdir(),
        check=False,
    )


def tree_digest(root):
    """Path -> sha256 for every file under root."""
    digests = {}
    for base, _, names in os.walk(root):
        for name in names:
            path = Path(base) / name
            digests[str(path.relative_to(root))] = hashlib.sha256(
                path.read_bytes()
            ).hexdigest()
    return digests


def convert(wxr_text, extra=(), media=True):
    """Write wxr_text to scratch space and convert it. Returns (proc, out, work)."""
    work = scratch()
    wxr = work / "export.xml"
    wxr.write_text(wxr_text, encoding="utf-8")
    out = work / "out"
    args = ["--wxr", wxr, "--out", out]
    if media:
        args += ["--media", make_media(work / "media")]
    args += list(extra)
    return run(args), out, work
