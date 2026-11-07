"""Compose a native screen capture with its matching Apple product bezel."""
import argparse
import io
from functools import lru_cache
from pathlib import Path

from PIL import Image, ImageCms, ImageDraw, ImageFont, ImageOps

DEVICES = {
    "iphone12": (1170, 2532),
    "iphone17pro": (1206, 2622),
    "iphone17promax": (1320, 2868),
    "ipad13": (2064, 2752),
    "duo-inner": (2007, 2853),
    "duo-inner-landscape": (2853, 2007),
    "duo-outer": (1398, 2034),
}

def screen_box(frame, size):
    """Locate the screen from the two straight edges through its horizontal centre."""
    alpha = frame.getchannel("A")
    w, h = frame.size
    row = alpha.crop((0, h // 2, w, h // 2 + 1))
    # Apple uses asymmetrical image padding on several models.
    left = next(x for x in range(w // 2, 0, -1) if row.getpixel((x, 0)) > 127) + 1
    right = next(x for x in range(w // 2, w) if row.getpixel((x, 0)) > 127)
    # A straight section near either edge clears both the notch and the rounded corners.
    columns = [left + (right - left) * n // 8 for n in (1, 2, 6, 7)]
    top = min(next(y for y in range(h // 2, 0, -1) if alpha.getpixel((col, y)) > 127)
              for col in columns) + 1
    bottom = max(next(y for y in range(h // 2, h) if alpha.getpixel((col, y)) > 127)
                 for col in columns)
    if abs((right - left) / (bottom - top) / (size[0] / size[1]) - 1) > 0.015:
        raise ValueError("Bezel aperture does not match the native screen aspect ratio")
    return left, top, right, bottom

@lru_cache(maxsize=1)
def screen_opening(frame_path, size):
    # Fill only the transparent opening. At the rounded corners both the exterior
    # and the opening are transparent in the original official PNG.
    with Image.open(frame_path) as bezel:
        box = screen_box(bezel, size)
        mask = bezel.getchannel("A").point(lambda a: 0 if a < 128 else 255)
        ImageDraw.floodfill(mask, (bezel.width // 2, bezel.height // 2), 128)
    return box, mask.point(lambda a: 255 if a == 128 else 0)

def framed(screen, bezel, box, mask):
    left, top, right, bottom = box
    layer = Image.new("RGBA", bezel.size)
    layer.paste(screen.resize((right-left, bottom-top), Image.Resampling.LANCZOS), (left, top))
    layer.putalpha(mask)
    return Image.alpha_composite(layer, bezel)

def render(args):
    size = DEVICES[args.device]
    with Image.open(args.frame) as bezel:
        if bezel.mode != "RGBA":
            raise ValueError("Expected an RGBA Apple bezel")
        box, opening = screen_opening(args.frame, size)
        if args.template:
            product = bezel.copy()
        else:
            with Image.open(args.screen) as screen:
                if screen.size != size:
                    raise ValueError(f"Expected a native {size} capture for {args.device}")
                profile = screen.info.get("icc_profile")
                rgb = screen.convert("RGB")
                if profile:
                    rgb = ImageCms.profileToProfile(rgb, io.BytesIO(profile), ImageCms.createProfile("sRGB"))
                product = framed(rgb, bezel, box, opening)
    w, h = size
    # Warm paper with a rose wash at the foot. An inset stitched border references
    # the wardrobe's sewing details and stays outside the product.
    bg = ImageOps.colorize(Image.linear_gradient("L").resize(size), "#fff7eb", "#edcfcc")
    d = ImageDraw.Draw(bg)
    accent = "#86565b"
    inset = round(w * .026)
    d.rounded_rectangle((inset, inset, w-inset, h-inset), radius=round(w*.026),
                        outline="#ddbdab", width=max(1, w//620))
    def line(copy, y, font_file, fraction, color, limit=.9, font_index=0):
        pts = round(w*fraction)
        while pts > 1:
            f = ImageFont.truetype(font_file, pts, index=font_index)
            if d.textlength(copy, font=f) <= w*limit:
                break
            pts -= 1
        if any(not f.getmask(c).getbbox() for c in copy if not c.isspace()):
            raise ValueError(f"Incomplete glyph coverage for {copy!r} in {font_file}")
        d.text((w / 2, h*y), copy, font=f, fill=color, anchor="mm")
    font_dir = Path("/System/Library/Fonts/Supplemental")
    title_font = "Baskerville.ttc" if args.title.isascii() else "Songti.ttc"
    title_face = 2 if args.locale == "zh-Hant" and title_font == "Songti.ttc" else 0
    if w > h:
        line(args.kicker, .054, str(font_dir/"Baskerville.ttc"), .013, accent)
        line(args.title, .109, str(font_dir/title_font), .045, "#59383f", font_index=title_face)
        line(args.caption, .168, "/System/Library/Fonts/STHeiti Light.ttc", .019, accent)
        top, height = .208, .75
    else:
        line(args.kicker, .052, str(font_dir/"Baskerville.ttc"), .024, accent)
        line(args.title, .110, str(font_dir/title_font), .080, "#59383f", font_index=title_face)
        line(args.caption, .170, "/System/Library/Fonts/STHeiti Light.ttc", .029, accent)
        top, height = .21, .75
    product.thumbnail((round(w*.92), round(h*height)), Image.Resampling.LANCZOS)
    origin = ((w-product.width)//2, round(h*top + (h*height-product.height)/2))
    bg.paste(product, origin, product)
    if args.template:
        bg = bg.convert("RGBA")
        aperture = opening.resize(product.size, Image.Resampling.LANCZOS)
        bg.paste((0, 0, 0, 0), origin, aperture)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    bg.save(args.output, "PNG", icc_profile=ImageCms.ImageCmsProfile(ImageCms.createProfile("sRGB")).tobytes())

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", choices=DEVICES, required=True)
    parser.add_argument("--locale", choices=("zh-Hans", "zh-Hant", "en"), default="zh-Hans")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--screen", type=Path)
    source.add_argument("--template", action="store_true", help="Export a transparent screen opening for layout work")
    for name in ("frame", "output"):
        parser.add_argument("--"+name, required=True, type=Path)
    for name in ("kicker", "title", "caption"):
        parser.add_argument("--"+name, required=True)
    render(parser.parse_args())
