"""Import named native XCTest captures; reject missing or wrong-sized scenes."""
import argparse
import json
import re
import shutil
from pathlib import Path

from PIL import Image

from frame_screenshot import DEVICES
from render_gallery import COPY, SCENES


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("device", choices=DEVICES)
    parser.add_argument("attachments", type=Path)
    parser.add_argument("--locales", nargs="+", choices=COPY, default=list(COPY))
    args = parser.parse_args()
    found = {}
    for test in json.loads((args.attachments / "manifest.json").read_text(encoding="utf-8")):
        for attachment in test["attachments"]:
            match = re.match(r"(zh-Hans|zh-Hant|en)-(wardrobe|payments|stats)_",
                             attachment["suggestedHumanReadableName"])
            if not match or attachment.get("isAssociatedWithFailure"):
                continue
            key = match.groups()
            if key[0] not in args.locales:
                continue
            if key in found:
                raise ValueError(f"Ambiguous capture: {key}")
            source = args.attachments / attachment["exportedFileName"]
            with Image.open(source) as photo:
                if photo.size != DEVICES[args.device]:
                    raise ValueError(f"Unexpected native size {photo.size}: {source}")
                photo.verify()
            found[key] = source
    expected = {(locale, scene) for locale in args.locales for scene in SCENES}
    if set(found) != expected:
        raise ValueError(f"Incomplete capture: missing {expected - set(found)}")
    for (locale, scene), source in found.items():
        destination = args.root / "raw" / locale / args.device / f"{scene}.png"
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
    print(f"Imported {len(found)} native captures for {args.device}; visual review still required.")


if __name__ == "__main__":
    main()
