from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PNG = ROOT / "assets" / "icons" / "ic_stat_vpn.png"
ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

if not PNG.is_file():
    raise SystemExit(f"Rendered PNG is missing: {PNG}")

with Image.open(PNG) as source:
    image = source.convert("RGBA")
    # Keep the in-app title mark unchanged; crop transparent margins only for
    # Windows taskbar artwork appears larger.
    # Ignore faint antialias/shadow pixels so transparent padding cannot shrink the artwork.
    alpha = image.getchannel("A").point(lambda value: 255 if value > 20 else 0)
    bounds = alpha.getbbox()
    if bounds is None:
        raise SystemExit(f"Rendered app icon is fully transparent: {PNG}")
    left, top, right, bottom = bounds
    # Crop exactly to visible artwork; do not add transparent padding.
    pad_x = 0
    pad_y = 0
    image = image.crop((
        max(0, left - pad_x),
        max(0, top - pad_y),
        min(image.width, right + pad_x),
        min(image.height, bottom + pad_y),
    ))

    # The source mark is 24x24. Pillow only emits ICO sizes no larger than
    # the input image, so upscale before saving to produce the full multi-size ICO.
    image = image.resize((256, 256), Image.Resampling.LANCZOS)

sizes = [(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
image.save(ICO, format="ICO", sizes=sizes)

# Keep the same BPB mark but shift its blue artwork to green for connected state.
hue, saturation, brightness = image.convert("HSV").split()
green_hue = Image.new("L", image.size, 96)
green = Image.merge("HSV", (green_hue, saturation, brightness)).convert("RGBA")
green.putalpha(image.getchannel("A"))
connected_ico = ICO.with_name("app_icon_connected.ico")
green.save(connected_ico, format="ICO", sizes=sizes)

print(f"Generated enlarged Windows shell icon: {ICO}")
print(f"Generated connected-state Windows shell icon: {connected_ico}")
