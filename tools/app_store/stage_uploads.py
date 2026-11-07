"""Stage ordered PNGs for Safari's native file picker, with a revision suffix."""
import argparse
import hashlib
import json
import shutil
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--revision", required=True)
    args = parser.parse_args()
    if not args.revision.isalnum():
        parser.error("Use an alphanumeric revision suffix")
    rows = []
    for source in sorted((args.root / "upload").glob("*/*/*.png")):
        locale, device, filename = source.relative_to(args.root / "upload").parts
        # Apple's Duo gallery shares one slot for both displays.
        slot = "duo" if device.startswith("duo-") else device
        destination = args.destination / locale / slot / f"{source.stem}-{args.revision}.png"
        if any(row["destination"] == str(destination) for row in rows):
            raise ValueError(f"Duplicate upload filename: {destination}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, destination)
        rows.append({"locale": locale, "slot": slot, "source": str(source),
                     "destination": str(destination),
                     "sha256": hashlib.sha256(destination.read_bytes()).hexdigest()})
    expected = {Path(row["destination"]) for row in rows}
    actual = set(args.destination.glob("*/*/*.png"))
    if actual != expected:
        raise ValueError(f"Unexpected stale staging files: {actual - expected}")
    (args.destination / "manifest.json").write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Staged {len(rows)} screenshots for Safari; online upload is a separate step.")


if __name__ == "__main__":
    main()
