from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
PNG = ROOT / "assets" / "icons" / "ic_stat_vpn.png"
ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

if not PNG.is_file():
    raise SystemExit(f"Rendered PNG is missing: {PNG}")

with Image.open(PNG) as image:
    image.convert("RGBA").save(
        ICO,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

print(f"Generated app-bar icon: {PNG}")
print(f"Generated Windows executable icon: {ICO}")
