from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
ICONS = ROOT / "assets" / "icons"
OUTPUT = ROOT / "windows" / "runner" / "resources"


def create_windows_icon(png_path: Path, ico_path: Path) -> None:
    if not png_path.is_file():
        raise SystemExit(f"Rendered PNG is missing: {png_path}")

    with Image.open(png_path) as source:
        image = source.convert("RGBA")
        # Ignore faint antialias/shadow pixels so transparent padding cannot shrink the artwork.
        alpha = image.getchannel("A").point(lambda value: 255 if value > 20 else 0)
        bounds = alpha.getbbox()
        if bounds is None:
            raise SystemExit(f"Rendered app icon is fully transparent: {png_path}")
        left, top, right, bottom = bounds
        image = image.crop((left, top, right, bottom))

        # The source mark is 24x24. Upscale to produce a full multi-size Windows ICO.
        image = image.resize((256, 256), Image.Resampling.LANCZOS)

    image.save(
        ico_path,
        format="ICO",
        sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)],
    )
    print(f"Generated Windows shell icon: {ico_path}")


create_windows_icon(ICONS / "ic_stat_vpn.png", OUTPUT / "app_icon.ico")
create_windows_icon(
    ICONS / "ic_stat_vpn_connected.png",
    OUTPUT / "app_icon_connected.ico",
)
