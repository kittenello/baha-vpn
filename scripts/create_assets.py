"""Generate the app's simple geometric icon; no external image assets."""
import json
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / "App" / "Assets.xcassets"
root.mkdir(parents=True, exist_ok=True)
(root / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}))
icon = root / "AppIcon.appiconset"
icon.mkdir(exist_ok=True)
image = Image.new("RGB", (1024, 1024), (17, 18, 23))
draw = ImageDraw.Draw(image)
draw.ellipse((155, 155, 869, 869), outline=(63, 55, 86), width=7)
draw.arc((284, 300, 740, 756), start=305, end=235, fill=(164, 133, 250), width=42)
draw.line((512, 269, 512, 498), fill=(164, 133, 250), width=42)
draw.ellipse((491, 248, 533, 290), fill=(164, 133, 250))
draw.ellipse((491, 477, 533, 519), fill=(164, 133, 250))
image.save(icon / "AppIcon.png")
(icon / "Contents.json").write_text(json.dumps({"images": [{"filename": "AppIcon.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}], "info": {"author": "xcode", "version": 1}}, indent=2))
color = root / "LaunchBackground.colorset"
color.mkdir(exist_ok=True)
(color / "Contents.json").write_text(json.dumps({"colors": [{"idiom": "universal", "color": {"color-space": "srgb", "components": {"red": "0.055", "green": "0.060", "blue": "0.075", "alpha": "1.000"}}}], "info": {"author": "xcode", "version": 1}}, indent=2))
