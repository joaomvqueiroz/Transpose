"""Builds the Transpono Firefox/Reynard extension (.xpi).

Reuses the app's page-local audio bridge from apps/mobile/assets/web so both
stay identical. Output: extensions/firefox/dist/transpono-firefox-<version>.xpi

Usage: python -I extensions/firefox/build.py
"""
import json
import shutil
import zipfile
from pathlib import Path

from PIL import Image

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
WEB = ROOT / "apps" / "mobile" / "assets" / "web"
ICON = ROOT / "apps" / "mobile" / "assets" / "branding" / "transpono_launcher.png"
STAGE = HERE / "build"
DIST = HERE / "dist"

WEB_FILES = [
    "SignalsmithStretch.js",
    "transpono_stretch.js",
    "transpono_key_detector.js",
    "transpono_media.js",
    "SIGNALSMITH_LICENSE.txt",
    "THIRD_PARTY.md",
]


def main() -> None:
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    if STAGE.exists():
        shutil.rmtree(STAGE)
    (STAGE / "web").mkdir(parents=True)
    (STAGE / "icons").mkdir()
    shutil.copy2(HERE / "manifest.json", STAGE / "manifest.json")
    shutil.copytree(HERE / "src", STAGE / "src")
    shutil.copytree(HERE / "popup", STAGE / "popup")
    for name in WEB_FILES:
        shutil.copy2(WEB / name, STAGE / "web" / name)
    with Image.open(ICON) as image:
        image = image.convert("RGBA")
        for size in (48, 96, 128):
            image.resize((size, size), Image.LANCZOS).save(STAGE / "icons" / f"icon-{size}.png")

    DIST.mkdir(exist_ok=True)
    target = DIST / f"transpono-firefox-{manifest['version']}.xpi"
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(STAGE.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(STAGE).as_posix())
    print(target)


if __name__ == "__main__":
    main()
