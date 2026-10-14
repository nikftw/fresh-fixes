# Flat white textures for the built-in waypoint (tinted in game).
# pin.tga: map pin (teardrop with a hole); pin_edge.tga: the same pin grown
# a few pixels, drawn black underneath as an outline; arrow.tga / arrow_edge.tga:
# chevron and its outline; beam.tga: vertical light beam under the pin.
from PIL import Image, ImageDraw, ImageFilter
import os
out = os.path.join(os.path.dirname(__file__), "..", "FreshFixes", "Media")
S = 4  # supersample
N = 64 * S

def save(img, name):
    img.resize((64, 64), Image.LANCZOS).save(os.path.join(out, name))

def white(mask):
    img = Image.new("RGBA", (N, N), (255, 255, 255, 0))
    img.putalpha(mask)
    return img

def grow(mask, px):
    return mask.filter(ImageFilter.MaxFilter(px * S * 2 + 1))

# pin: circle head + point, hole in the middle
m = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(m)
cx, cy, r = 32 * S, 23 * S, 17 * S
d.ellipse((cx - r, cy - r, cx + r, cy + r), fill=255)
d.polygon([(cx - 14.5 * S, cy + 9 * S), (cx + 14.5 * S, cy + 9 * S), (cx, 60 * S)], fill=255)
edge = grow(m, 3)
h = 7 * S
d.ellipse((cx - h, cy - h, cx + h, cy + h), fill=0)
save(white(m), "pin.tga")
save(white(edge), "pin_edge.tga")

# arrow: chevron pointing up
m = Image.new("L", (N, N), 0)
d = ImageDraw.Draw(m)
d.polygon([(32 * S, 8 * S), (56 * S, 54 * S), (32 * S, 42 * S), (8 * S, 54 * S)], fill=255)
save(white(m), "arrow.tga")
save(white(grow(m, 3)), "arrow_edge.tga")

# beam: soft vertical line, strong at the bottom, fading upwards
b = Image.new("L", (N, N), 0)
px = b.load()
for y in range(N):
    for x in range(N):
        dx = abs(x - N / 2) / (N / 2)
        a = max(0.0, 1 - dx * 4) ** 1.5 * (y / N) ** 1.2
        px[x, y] = int(255 * a)
save(white(b), "beam.tga")
print("ok")
