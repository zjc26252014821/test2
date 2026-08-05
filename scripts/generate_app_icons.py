from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]


def draw_icon(size: int) -> Image.Image:
    image = Image.new("RGB", (size, size), "#16324a")
    draw = ImageDraw.Draw(image)
    margin = round(size * 0.18)
    gap = round(size * 0.055)
    cell = (size - margin * 2 - gap) // 2
    colors = ("#39c6a5", "#f2c14e", "#e9f2f7", "#4da3ff")
    index = 0
    for row in range(2):
        for column in range(2):
            x = margin + column * (cell + gap)
            y = margin + row * (cell + gap)
            radius = max(2, round(size * 0.045))
            draw.rounded_rectangle((x, y, x + cell, y + cell), radius=radius, fill=colors[index])
            index += 1
    triangle = [
        (round(size * 0.44), round(size * 0.38)),
        (round(size * 0.44), round(size * 0.62)),
        (round(size * 0.63), round(size * 0.50)),
    ]
    draw.polygon(triangle, fill="#16324a")
    return image


def main() -> None:
    for scale in (2, 3):
        output = ROOT / "app" / f"AppIcon60x60@{scale}x.png"
        draw_icon(60 * scale).save(output, format="PNG", optimize=True)
        print(output)


if __name__ == "__main__":
    main()
