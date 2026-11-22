import sys
from pathlib import Path
from playwright.sync_api import sync_playwright

# WA palette (from world-assistant/deploy/unraid/make_icons.py)
BG = "#14231a"    # deep green-black tile
LAND = "#4cc15a"
SEA = "#1f3b2a"
BAND = "#12a594"  # WA routing teal, distinct from the green globe

# Globe reused from WA, shrunk and lifted so two bands fit above and below.
GLOBE = f"""
  <defs><clipPath id="ball"><circle cx="128" cy="98" r="52"/></clipPath></defs>
  <circle cx="128" cy="98" r="52" fill="{SEA}"/>
  <g clip-path="url(#ball)" fill="{LAND}" transform="translate(128 98) scale(.86) translate(-128 -108)">
    <path d="M70 62c14-14 38-18 52-8 6 5 2 12-6 16-9 5-6 14-16 18-11 5-18 14-16 26 2 9-4 14-12 8-14-11-22-38-2-60z"/>
    <path d="M142 118c10-8 26-6 36 4 10 11 14 28 6 42-8 13-22 14-26 4-3-8-12-10-14-20-2-11-6-22-2-30z"/>
    <path d="M150 46c10-6 24-4 32 6 5 6 0 12-8 12-8 0-10 8-18 6-9-2-14-18-6-24z"/>
  </g>
  <circle cx="128" cy="98" r="52" fill="none" stroke="{LAND}" stroke-width="8"/>
"""

# A short data cable hanging from the globe, ending in a centred smartphone (replaces the USB plug).
PHONE = f"""
  <path d="M128 150 C128 156 128 156 128 160" fill="none" stroke="{LAND}" stroke-width="7" stroke-linecap="round"/>
  <rect x="109" y="158" width="38" height="48" rx="7.5" fill="{LAND}"/>
  <rect x="114" y="166" width="28" height="32" rx="2.5" fill="{BG}"/>
  <rect x="123" y="162" width="10" height="2.6" rx="1.3" fill="{BG}"/>
  <circle cx="128" cy="202.5" r="2.4" fill="{BG}"/>
"""

def band(text, y):
    size = 25 if len(text) <= 6 else 22
    return (f'<rect x="24" y="{y}" width="208" height="34" rx="17" fill="{BAND}"/>'
            f'<text x="128" y="{y+24}" text-anchor="middle" '
            f'font-family="DejaVu Sans, Arial, Helvetica, sans-serif" '
            f'font-weight="800" font-size="{size}" letter-spacing="2" fill="#ffffff">{text}</text>')

# Full opaque square (no rounded corners) — iOS applies its own mask.
SVG = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="1024" height="1024">'
       f'<rect width="256" height="256" fill="{BG}"/>'
       f'{GLOBE}{PHONE}{band("MCP", 12)}{band("INTENT", 210)}</svg>')

out = Path(sys.argv[1])
out.parent.mkdir(parents=True, exist_ok=True)
with sync_playwright() as p:
    b = p.chromium.launch(args=["--no-sandbox"])
    pg = b.new_page(viewport={"width": 1024, "height": 1024})
    pg.set_content(f'<html><body style="margin:0">{SVG}</body></html>')
    pg.screenshot(path=str(out), clip={"x": 0, "y": 0, "width": 1024, "height": 1024})
    b.close()
print("wrote", out)
