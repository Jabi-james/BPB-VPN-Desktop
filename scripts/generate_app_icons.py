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
    # Windows shell icons so the taskbar and tray artwork appears larger.
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

image.save(
    ICO,
    format="ICO",
    sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
)

print(f"Generated enlarged Windows shell icon: {ICO}")
