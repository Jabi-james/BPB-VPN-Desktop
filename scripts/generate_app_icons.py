from pathlib import Path
import cairosvg
from PIL import Image
import io

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "icons" / "bpb_icon.svg"
PNG = ROOT / "assets" / "icons" / "ic_stat_vpn.png"
ICO = ROOT / "windows" / "runner" / "resources" / "app_icon.ico"

# Render the supplied adaptive foreground as a transparent, two-tone blue icon.
png_bytes = cairosvg.svg2png(url=str(SOURCE), output_width=256, output_height=256)
PNG.parent.mkdir(parents=True, exist_ok=True)
PNG.write_bytes(png_bytes)

with Image.open(io.BytesIO(png_bytes)) as image:
    image.convert("RGBA").save(
        ICO,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )

print(f"Generated app-bar icon: {PNG}")
print(f"Generated Windows executable icon: {ICO}")
